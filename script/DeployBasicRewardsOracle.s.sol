// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {BasicRewardsOracle} from "../src/periphery/BasicRewardsOracle.sol";

contract DeployBasicRewardsOracle is Script {
    // Chain IDs
    uint256 constant ETHEREUM_CHAIN_ID = 1;
    uint256 constant BASE_CHAIN_ID = 8453;
    uint256 constant KATANA_CHAIN_ID = 3737; // Katana's chain ID
    uint256 constant POLYGON_CHAIN_ID = 137;

    // Governance addresses per chain
    address public governance = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // MORPHO token addresses per chain
    mapping(uint256 => address) public morphoToken;

    // MORPHO/WETH or MORPHO/ETH pool addresses per chain
    mapping(uint256 => address) public morphoWethPool;

    // WETH/USD or ETH/USD oracle addresses per chain
    mapping(uint256 => address) public wethUsdOracle;

    function setUp() public {
        // Ethereum Mainnet configuration
        morphoToken[ETHEREUM_CHAIN_ID] = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
        morphoWethPool[ETHEREUM_CHAIN_ID] = 0x25b96761e765b9AC20db18fA57Fa91e3b617Ec6F; // MORPHO/WETH 0.3%
        wethUsdOracle[ETHEREUM_CHAIN_ID] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink WETH/USD

        // Base configuration
        morphoToken[BASE_CHAIN_ID] = 0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842; // MORPHO on Base
        morphoWethPool[BASE_CHAIN_ID] = address(0); // TODO: Set MORPHO/WETH pool on Base
        wethUsdOracle[BASE_CHAIN_ID] = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70; // Chainlink ETH/USD on Base

        // Katana configuration
        morphoToken[KATANA_CHAIN_ID] = 0x1e5eFCA3D0dB2c6d5C67a4491845c43253eB9e4e; // TODO: Set MORPHO on Katana
        morphoWethPool[KATANA_CHAIN_ID] = 0x42C00599d9008E56e4E2e570cA27ea46EAE5d89a; // TODO: Set MORPHO/ETH pool on Katana
        wethUsdOracle[KATANA_CHAIN_ID] = 0x7BdBDB772f4a073BadD676A567C6ED82049a8eEE; // TODO: Set ETH/USD oracle on Katana

        // Polygon configuration
        morphoToken[POLYGON_CHAIN_ID] = address(0); // TODO: Set MORPHO on Polygon if exists
        morphoWethPool[POLYGON_CHAIN_ID] = address(0); // TODO: Set MORPHO/WETH pool on Polygon
        wethUsdOracle[POLYGON_CHAIN_ID] = 0xF9680D99D6C9589e2a93a78A04A279e509205945; // Chainlink ETH/USD on Polygon
    }

    function run() external returns (address oracle) {
        uint256 chainId = block.chainid;

        // Get configuration for current chain
        address _governance = governance;
        address _morphoToken = morphoToken[chainId];
        address _morphoWethPool = morphoWethPool[chainId];
        address _wethUsdOracle = wethUsdOracle[chainId];


        // Log deployment parameters
        console.log("Deploying BasicRewardsOracle on chain:", chainId);
        console.log("Governance:", _governance);
        console.log("MORPHO Token:", _morphoToken);
        console.log("MORPHO/WETH Pool:", _morphoWethPool);
        console.log("WETH/USD Oracle:", _wethUsdOracle);

        vm.startBroadcast();

        // Deploy the oracle
        oracle = address(new BasicRewardsOracle(_governance));

        // If MORPHO configuration is available, set it
        if (chainId != ETHEREUM_CHAIN_ID) {
            BasicRewardsOracle(oracle).setMorphoPricing(
                _morphoToken,
                _morphoWethPool,
                _wethUsdOracle
            );
            console.log("MORPHO pricing configured");
        }

        vm.stopBroadcast();

        console.log("BasicRewardsOracle deployed at:", oracle);

        return oracle;
    }
    // Helper function to update configuration after deployment
    function updateMorphoPricing(
        address oracle,
        address _morphoToken,
        address _morphoWethPool,
        address _wethUsdOracle
    ) external {
        vm.startBroadcast();

        BasicRewardsOracle(oracle).setMorphoPricing(
            _morphoToken,
            _morphoWethPool,
            _wethUsdOracle
        );

        vm.stopBroadcast();

        console.log("MORPHO pricing updated for oracle:", oracle);
    }
}