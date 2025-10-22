// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {Simulate, IUniswapV3Pool} from "@uniswap-v3-core/libraries/Simulate.sol";

/**
 * @title IMorphoGenericOracle
 * @notice Interface for Morpho reward oracles
 */
interface IMorphoGenericOracle {
    /**
     * @notice Get the rewards rate for a vault
     * @param _vault The vault to get rewards rate for
     * @return The rewards APR as 1e18 (e.g., 10% = 1e17)
     */
    function getRewardsRate(address _vault) external view returns (uint256);
}

/**
 * @title IOracle
 * @notice Interface for price oracles (Chainlink compatible)
 */
interface IOracle {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

/**
 * @title BasicRewardsOracle
 * @author Your Protocol
 * @notice Oracle for calculating reward APR for Morpho compounders including MORPHO rewards
 * @dev This oracle uses Uniswap V3 for MORPHO pricing and oracle feeds for other tokens
 */
contract BasicRewardsOracle is IMorphoGenericOracle, Governance {
    // ========================================
    // ============= STRUCTS ==================
    // ========================================

    /**
     * @notice Reward token configuration
     * @param token Address of the reward token
     * @param priceOracle Address of the price oracle for this token
     * @param rewardRate Reward rate per second in token units (with token decimals)
     * @param decimals Token decimals
     */
    struct RewardToken {
        address token;
        address priceOracle;
        uint256 rewardRate;
        uint8 decimals;
    }

    /**
     * @notice Vault rewards configuration
     * @param morphoRate MORPHO tokens per year (set by governance, like morphoRate in MorphoAprOracle)
     * @param rewardTokens Array of additional reward tokens for this vault
     * @param assetDecimals Decimals of the vault's asset
     * @param assetPriceOracle Price oracle for the vault's asset
     */
    struct VaultRewards {
        uint256 morphoRate; // Annual MORPHO rewards
        RewardToken[] rewardTokens;
        uint8 assetDecimals;
        address assetPriceOracle;
    }

    // ========================================
    // ============= CONSTANTS ================
    // ========================================

    uint256 public constant WAD = 1e18;
    uint256 public constant ORACLE_DECIMALS = 1e8; // Standard oracle decimals (8)
    uint256 public constant SECONDS_PER_YEAR = 31_556_952; // Seconds in a year
    uint256 public constant MAX_BPS = 10_000;

    // Uniswap V3 sqrt price limits
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    // ========================================
    // ============= STORAGE ==================
    // ========================================

    /// @notice Vault rewards configuration
    mapping(address => VaultRewards) public vaultRewards;

    /// @notice Default oracle decimals (8 for Chainlink on mainnet)
    uint8 public defaultOracleDecimals = 8;

    /// @notice Global MORPHO pricing configuration
    address public morphoToken;
    address public morphoWethPool;
    IOracle public wethUsdOracle;
    uint256 public per = 1e8;
    // ========================================
    // ============= EVENTS ===================
    // ========================================

    event VaultRewardsUpdated(
        address indexed vault,
        uint256 morphoRate,
        uint256 rewardTokenCount
    );
    event MorphoRateUpdated(address indexed vault, uint256 morphoRate);
    event RewardTokenAdded(
        address indexed vault,
        address indexed token,
        uint256 rewardRate
    );
    event RewardTokenRemoved(address indexed vault, address indexed token);

    // ========================================
    // ============= CONSTRUCTOR ==============
    // ========================================

    /**
     * @notice Constructor
     * @param _governance Address of the governance contract
     */
    constructor(address _governance) Governance(_governance) {
        // Set default MORPHO pricing configuration (Mainnet defaults)
        morphoToken = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2; // MORPHO on mainnet
        morphoWethPool = 0x25b96761e765b9AC20db18fA57Fa91e3b617Ec6F;
        wethUsdOracle = IOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    // ========================================
    // ========= EXTERNAL FUNCTIONS ===========
    // ========================================

    /**
     * @notice Get the rewards APR for a vault
     * @param _vault The vault to get rewards rate for
     * @return totalAPR The total rewards APR as 1e18
     */
    function getRewardsRate(
        address _vault
    ) external view override returns (uint256 totalAPR) {
        VaultRewards storage rewards = vaultRewards[_vault];

        // Return 0 if no rewards configured
        if (rewards.morphoRate == 0 && rewards.rewardTokens.length == 0) {
            return 0;
        }

        // Calculate the USD value of the vault's TVL (in 1e8 decimals)
        uint256 tvlUSD = _getTokenValueUSD(
            IStrategyInterface(_vault).totalAssets(),
            rewards.assetPriceOracle,
            rewards.assetDecimals
        );

        if (tvlUSD == 0) return 0;

        // Calculate MORPHO rewards APR (if configured)
        if (rewards.morphoRate > 0) {
            uint256 morphoAPR = _getMorphoAPR(rewards.morphoRate);
            totalAPR += morphoAPR;
        }

        // Sum up APR from all additional reward tokens
        for (uint256 i = 0; i < rewards.rewardTokens.length; i++) {
            RewardToken memory rewardToken = rewards.rewardTokens[i];

            if (rewardToken.rewardRate == 0) continue;

            uint256 annualRewardAmount = rewardToken.rewardRate *
                SECONDS_PER_YEAR;

            // Get the USD value of annual rewards (in 1e8 decimals)
            uint256 annualRewardUSD = _getTokenValueUSD(
                annualRewardAmount,
                rewardToken.priceOracle,
                rewardToken.decimals
            );

            // Calculate APR: (annual reward USD / TVL USD) * 1e18
            // Both values are in 1e8, so result needs to be scaled to 1e18
            uint256 tokenAPR = (annualRewardUSD * WAD) / tvlUSD;

            totalAPR += tokenAPR;
        }

        return totalAPR;
    }

    // ========================================
    // ======= GOVERNANCE FUNCTIONS ===========
    // ========================================

    /**
     * @notice Set complete rewards configuration for a vault
     * @param _vault The vault address
     * @param _morphoRate Annual MORPHO rewards (like morphoRate in MorphoAprOracle)
     * @param _tokens Array of additional reward token addresses
     * @param _priceOracles Array of price oracle addresses for additional tokens
     * @param _rewardRates Array of reward rates per second for additional tokens
     * @param _assetPriceOracle Price oracle for the vault's asset
     */
    function setVaultRewards(
        address _vault,
        uint256 _morphoRate,
        address[] calldata _tokens,
        address[] calldata _priceOracles,
        uint256[] calldata _rewardRates,
        address _assetPriceOracle
    ) external onlyGovernance {
        require(_vault != address(0), "Invalid vault");
        require(
            _tokens.length == _priceOracles.length &&
                _tokens.length == _rewardRates.length,
            "Array length mismatch"
        );

        // Clear existing rewards
        delete vaultRewards[_vault].rewardTokens;

        VaultRewards storage rewards = vaultRewards[_vault];

        // Set MORPHO rate
        rewards.morphoRate = _morphoRate;

        // Set asset configuration
        rewards.assetPriceOracle = _assetPriceOracle;
        rewards.assetDecimals = IStrategyInterface(IStrategyInterface(_vault).asset()).decimals();

        // Add additional reward tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), "Invalid token");
            require(_priceOracles[i] != address(0), "Invalid price oracle");

            rewards.rewardTokens.push(
                RewardToken({
                    token: _tokens[i],
                    priceOracle: _priceOracles[i],
                    rewardRate: _rewardRates[i],
                    decimals: ERC20(_tokens[i]).decimals()
                })
            );

            emit RewardTokenAdded(_vault, _tokens[i], _rewardRates[i]);
        }

        emit VaultRewardsUpdated(_vault, _morphoRate, _tokens.length);
    }

    /**
     * @notice Set global Uniswap V3 pool for MORPHO pricing
     * @param _morphoToken MORPHO token address
     * @param _morphoWethPool MORPHO/WETH Uniswap V3 pool address
     * @param _wethUsdOracle Oracle for WETH/USD pricing
     */
    function setMorphoPricing(
        address _morphoToken,
        address _morphoWethPool,
        address _wethUsdOracle
    ) external onlyGovernance {
        require(_morphoToken != address(0), "Invalid token");
        require(_morphoWethPool != address(0), "Invalid pool");
        require(_wethUsdOracle != address(0), "Invalid oracle");

        morphoToken = _morphoToken;
        morphoWethPool = _morphoWethPool;
        wethUsdOracle = IOracle(_wethUsdOracle);
    }

    /**
     * @notice Update MORPHO rate for a vault
     * @param _vault The vault address
     * @param _morphoRate New annual MORPHO rewards
     */
    function setMorphoRate(
        address _vault,
        uint256 _morphoRate
    ) external onlyGovernance {
        require(_vault != address(0), "Invalid vault");
        vaultRewards[_vault].morphoRate = _morphoRate;
        emit MorphoRateUpdated(_vault, _morphoRate);
    }

    /**
     * @notice Update MORPHO rates for multiple vaults
     * @param _vaults Array of vault addresses
     * @param _morphoRates Array of annual MORPHO rewards
     */
    function setMorphoRates(
        address[] calldata _vaults,
        uint256[] calldata _morphoRates
    ) external onlyGovernance {
        require(_vaults.length == _morphoRates.length, "Array length mismatch");

        for (uint256 i = 0; i < _vaults.length; i++) {
            require(_vaults[i] != address(0), "Invalid vault");
            vaultRewards[_vaults[i]].morphoRate = _morphoRates[i];
            emit MorphoRateUpdated(_vaults[i], _morphoRates[i]);
        }
    }

    function setPer(uint256 _per) external onlyGovernance {
        per = _per;
    }

    /**
     * @notice Update reward rate for a specific additional token
     * @param _vault The vault address
     * @param _tokenIndex Index of the token in the rewards array
     * @param _rewardRate New reward rate per second in token units
     */
    function updateRewardRate(
        address _vault,
        uint256 _tokenIndex,
        uint256 _rewardRate
    ) external onlyGovernance {
        require(_vault != address(0), "Invalid vault");
        require(
            _tokenIndex < vaultRewards[_vault].rewardTokens.length,
            "Invalid token index"
        );

        vaultRewards[_vault].rewardTokens[_tokenIndex].rewardRate = _rewardRate;
    }

    /**
     * @notice Update price oracle for a reward token
     * @param _vault The vault address
     * @param _tokenIndex Index of the token in the rewards array
     * @param _priceOracle New price oracle address
     */
    function updatePriceOracle(
        address _vault,
        uint256 _tokenIndex,
        address _priceOracle
    ) external onlyGovernance {
        require(_vault != address(0), "Invalid vault");
        require(
            _tokenIndex < vaultRewards[_vault].rewardTokens.length,
            "Invalid token index"
        );
        require(_priceOracle != address(0), "Invalid price oracle");

        vaultRewards[_vault]
            .rewardTokens[_tokenIndex]
            .priceOracle = _priceOracle;
    }

    /**
     * @notice Remove all rewards for a vault
     * @param _vault The vault address
     */
    function removeVaultRewards(address _vault) external onlyGovernance {
        delete vaultRewards[_vault];
        emit VaultRewardsUpdated(_vault, 0, 0);
    }

    // ========================================
    // ========== VIEW FUNCTIONS ==============
    // ========================================

    /**
     * @notice Get MORPHO rewards rate for a vault
     * @param _vault The vault address
     * @return MORPHO rewards APR as 1e18
     */
    function getMorphoRewardsRate(
        address _vault
    ) external view returns (uint256) {
        VaultRewards storage rewards = vaultRewards[_vault];

        if (rewards.morphoRate == 0) return 0;

        return _getMorphoAPR(rewards.morphoRate);
    }

    /**
     * @notice Get reward tokens for a vault
     * @param _vault The vault address
     * @return Array of reward tokens
     */
    function getVaultRewardTokens(
        address _vault
    ) external view returns (RewardToken[] memory) {
        return vaultRewards[_vault].rewardTokens;
    }

    /**
     * @notice Get vault configuration
     * @param _vault The vault address
     * @return morphoRate Annual MORPHO rewards
     * @return assetPriceOracle Asset price oracle
     * @return rewardTokenCount Number of additional reward tokens
     */
    function getVaultConfig(
        address _vault
    )
        external
        view
        returns (
            uint256 morphoRate,
            address assetPriceOracle,
            uint256 rewardTokenCount
        )
    {
        VaultRewards storage rewards = vaultRewards[_vault];
        return (
            rewards.morphoRate,
            rewards.assetPriceOracle,
            rewards.rewardTokens.length
        );
    }

    // ========================================
    // ======== INTERNAL FUNCTIONS ============
    // ========================================

    /**
     * @notice Calculate MORPHO rewards APR
     * @param morphoRate Annual MORPHO rewards
     * @return MORPHO APR in 1e18
     */
    function _getMorphoAPR(uint256 morphoRate) internal view returns (uint256) {
        if (morphoRate == 0 || morphoWethPool == address(0)) return 0;

        IUniswapV3Pool pool = IUniswapV3Pool(morphoWethPool);

        // Determine swap direction based on token order in the pool
        address token0 = pool.token0();
        address token1 = pool.token1();

        bool zeroForOne;
        if (token0 == morphoToken) {
            zeroForOne = true; // MORPHO -> WETH
        } else if (token1 == morphoToken) {
            zeroForOne = false; // WETH <- MORPHO
        } else {
            return 0; // Invalid pool configuration
        }

        // Simulate swap to get MORPHO price in WETH
        (, int256 wethAmount) = Simulate.simulateSwap(
            pool,
            zeroForOne,
            int256(morphoRate),
            zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        );

        // WETH amount should be negative (outgoing) regardless of swap direction
        if (wethAmount >= 0) return 0;

        // Get WETH price in USD
        uint256 wethPrice = _getOraclePrice(address(wethUsdOracle));
        if (wethPrice == 0) return 0;

        return (uint256(-wethAmount) * wethPrice) / per;
    }

    /**
     * @notice Get USD value of tokens
     * @param _amount Token amount with decimals
     * @param _priceOracle Price oracle address
     * @param _tokenDecimals Token decimals
     * @return USD value scaled to 1e8 (standard oracle decimals)
     */
    function _getTokenValueUSD(
        uint256 _amount,
        address _priceOracle,
        uint8 _tokenDecimals
    ) internal view returns (uint256) {
        if (_amount == 0) return 0;

        // If no price oracle is set, assume 1:1 with USD (for stablecoins)
        if (_priceOracle == address(0)) {
            // Convert to 1e8 precision
            return (_amount * ORACLE_DECIMALS) / (10 ** _tokenDecimals);
        }

        uint256 price = _getOraclePrice(_priceOracle);
        if (price == 0) return 0;

        // Convert to 1e8 precision
        return (_amount * price) / (10 ** _tokenDecimals);
    }

    /**
     * @notice Get price from oracle
     * @param _oracle Oracle address
     * @return Price in 8 decimals
     */
    function _getOraclePrice(address _oracle) internal view returns (uint256) {
        if (_oracle == address(0)) return ORACLE_DECIMALS; // $1 default

        try IOracle(_oracle).latestAnswer() returns (int256 price) {
            if (price <= 0) return 0;

            // Get oracle decimals, fallback to default if not available
            uint8 oracleDecimals = _getOracleDecimals(_oracle);

            // Normalize to 8 decimals
            if (oracleDecimals == 8) {
                return uint256(price);
            } else if (oracleDecimals < 8) {
                return uint256(price) * 10 ** (8 - oracleDecimals);
            } else {
                return uint256(price) / 10 ** (oracleDecimals - 8);
            }
        } catch {
            return 0;
        }
    }

    /**
     * @notice Get oracle decimals with fallback
     * @param _oracle Oracle address
     * @return decimals Oracle decimals
     */
    function _getOracleDecimals(address _oracle) internal view returns (uint8) {
        try IOracle(_oracle).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return defaultOracleDecimals;
        }
    }
}
