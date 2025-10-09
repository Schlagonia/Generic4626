// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

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
 * @notice Oracle for calculating reward APR for Morpho compounders
 * @dev This oracle fetches prices on-chain and calculates APR based on governance-set reward rates
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
     * @param rewardTokens Array of reward tokens for this vault
     * @param totalValueLocked TVL in asset units (with asset decimals)
     * @param assetDecimals Decimals of the vault's asset
     * @param assetPriceOracle Price oracle for the vault's asset
     * @param lastUpdated Timestamp of last update
     */
    struct VaultRewards {
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
    uint256 public constant MAX_REWARD_TOKENS = 10; // Maximum reward tokens per vault
    uint256 public constant PRECISION_FACTOR = 1e36; // High precision for calculations

    // ========================================
    // ============= STORAGE ==================
    // ========================================

    /// @notice Vault rewards configuration
    mapping(address => VaultRewards) public vaultRewards;

    /// @notice Default oracle decimals (8 for Chainlink on mainnet)
    uint8 public defaultOracleDecimals = 8;

    // ========================================
    // ============= EVENTS ===================
    // ========================================

    event VaultRewardsUpdated(address indexed vault, uint256 rewardTokenCount);
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
    constructor(address _governance) Governance(_governance) {}

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

        // Return 0 if no rewards configured or TVL is 0
        if (rewards.rewardTokens.length == 0) {
            return 0;
        }

        // Calculate the USD value of the vault's TVL (in 1e8 decimals)
        uint256 tvlUSD = _getTokenValueUSD(
            IStrategyInterface(_vault).totalAssets(),
            rewards.assetPriceOracle,
            rewards.assetDecimals
        );

        if (tvlUSD == 0) return 0;

        // Sum up APR from all reward tokens
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
     * @notice Set rewards configuration for a vault
     * @param _vault The vault address
     * @param _tokens Array of reward token addresses
     * @param _priceOracles Array of price oracle addresses
     * @param _rewardRates Array of reward rates per second in token units
     * @param _assetPriceOracle Price oracle for the vault's asset
     */
    function setVaultRewards(
        address _vault,
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
        require(_tokens.length <= MAX_REWARD_TOKENS, "Too many reward tokens");

        // Clear existing rewards
        delete vaultRewards[_vault].rewardTokens;

        VaultRewards storage rewards = vaultRewards[_vault];
        rewards.assetPriceOracle = _assetPriceOracle;
        rewards.assetDecimals = ERC20(IStrategyInterface(_vault).asset())
            .decimals();

        // Add reward tokens
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

        emit VaultRewardsUpdated(_vault, _tokens.length);
    }

    /**
     * @notice Update reward rate for a specific token
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
        emit VaultRewardsUpdated(_vault, 0);
    }

    // ========================================
    // ========== VIEW FUNCTIONS ==============
    // ========================================

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
     * @return assetPriceOracle Asset price oracle
     * @return rewardTokenCount Number of reward tokens
     */
    function getVaultConfig(
        address _vault
    )
        external
        view
        returns (address assetPriceOracle, uint256 rewardTokenCount)
    {
        VaultRewards storage rewards = vaultRewards[_vault];
        return (rewards.assetPriceOracle, rewards.rewardTokens.length);
    }

    // ========================================
    // ======== INTERNAL FUNCTIONS ============
    // ========================================

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

        try IOracle(_priceOracle).latestAnswer() returns (int256 price) {
            if (price <= 0) return 0;

            // Get oracle decimals, fallback to default if not available
            uint8 oracleDecimals = _getOracleDecimals(_priceOracle);

            // Convert to 1e8 precision
            // amount * price * 1e8 / (10^tokenDecimals * 10^oracleDecimals)
            return
                (_amount * uint256(price) * ORACLE_DECIMALS) /
                (10 ** _tokenDecimals * 10 ** oracleDecimals);
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
