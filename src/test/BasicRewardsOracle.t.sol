// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {BasicRewardsOracle} from "../periphery/BasicRewardsOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock price oracle for testing
contract MockPriceOracle {
    int256 public price;
    uint8 public decimals;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
    }

    function latestAnswer() external view returns (int256) {
        return price;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract BasicRewardsOracleTest is Setup {
    BasicRewardsOracle public rewardsOracle;
    MockPriceOracle public assetPriceOracle;
    MockPriceOracle public rewardTokenOracle;
    MockPriceOracle public secondRewardTokenOracle;

    address public governance = address(1);
    address public morphoToken;
    address public wethToken;

    function setUp() public virtual override {
        super.setUp();

        // Deploy the rewards oracle
        rewardsOracle = new BasicRewardsOracle(governance);

        // Create mock price oracles with 8 decimals (standard Chainlink format)
        assetPriceOracle = new MockPriceOracle(1e8, 8); // $1 for stablecoin
        rewardTokenOracle = new MockPriceOracle(5e8, 8); // $5 per reward token
        secondRewardTokenOracle = new MockPriceOracle(2000e8, 8); // $2000 per token

        // Use existing tokens from Setup
        morphoToken = tokenAddrs["LINK"]; // Using LINK as mock MORPHO token
        wethToken = tokenAddrs["WETH"];
    }

    function test_basicRewardsCalculation() public {
        // Setup reward configuration
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        // 100 tokens per day = ~1.157e15 per second
        uint256 rewardPerSecond = 1157407407407407407; // 100e18 / 86400
        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = rewardPerSecond;

        // Configure rewards as governance
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Deposit some funds into strategy to have TVL
        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        // Since the oracle now uses IStrategyInterface(_vault).vault().totalAssets(),
        // we need to check the actual vault's TVL
        uint256 vaultAssets = ERC20(vault).totalSupply();
        console.log("Vault total assets:", vaultAssets);

        // Calculate expected APR
        // Annual rewards: 100 tokens/day * 365.25 days = 36,525 tokens
        // Value: 36,525 * $5 = $182,625
        // TVL will be based on vault's totalAssets

        uint256 apr = rewardsOracle.getRewardsRate(address(strategy));

        console.log("Calculated APR:", apr);

        // APR should be positive and reasonable
        assertGt(apr, 0, "APR should be positive");
        assertLt(apr, 200e18, "APR unreasonably high");

        // Log the actual APR for debugging
        console.log("Calculated APR (in 1e18):", apr);
        console.log("Calculated APR (as %):", (apr * 100) / 1e18);
    }

    function test_multipleRewardTokens() public {
        // Setup multiple reward tokens
        address[] memory tokens = new address[](2);
        tokens[0] = morphoToken;
        tokens[1] = wethToken;

        address[] memory oracles = new address[](2);
        oracles[0] = address(rewardTokenOracle); // $5
        oracles[1] = address(secondRewardTokenOracle); // $2000

        uint256[] memory rewardRates = new uint256[](2);
        rewardRates[0] = 1157407407407407407; // 100 MORPHO per day (100e18 / 86400)
        rewardRates[1] = 11574074074074074; // 1 WETH per day (1e18 / 86400)

        // Configure rewards
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Deposit funds
        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        uint256 multiTokenApr = rewardsOracle.getRewardsRate(address(strategy));

        // Now update to only use first token
        rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        tokens = new address[](1);
        tokens[0] = morphoToken;

        oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        uint256 singleTokenApr = rewardsOracle.getRewardsRate(
            address(strategy)
        );

        console.log("APR with multiple rewards:", multiTokenApr);
        console.log("APR with single reward:", singleTokenApr);

        // Multiple token APR should be higher than single token
        assertGt(
            multiTokenApr,
            singleTokenApr,
            "Multiple rewards should give higher APR"
        );
    }

    function test_zeroRewards() public {
        // Test with no rewards configured
        uint256 apr = rewardsOracle.getRewardsRate(address(strategy));
        assertEq(apr, 0, "APR should be 0 with no rewards");

        // Configure rewards with zero rates
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 0;

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        apr = rewardsOracle.getRewardsRate(address(strategy));
        assertEq(apr, 0, "APR should be 0 with zero reward rate");
    }

    function test_updateRewardRate() public {
        // Initial setup
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        uint256 initialApr = rewardsOracle.getRewardsRate(address(strategy));

        // Double the reward rate
        vm.prank(governance);
        rewardsOracle.updateRewardRate(
            address(strategy),
            0,
            2314814814814814814
        ); // 200e18 / 86400

        uint256 newApr = rewardsOracle.getRewardsRate(address(strategy));

        console.log("Initial APR:", initialApr);
        console.log("New APR:", newApr);

        // APR should approximately double
        assertGt(
            newApr,
            (initialApr * 195) / 100,
            "APR didn't increase enough"
        );
        assertLt(newApr, (initialApr * 205) / 100, "APR increased too much");
    }

    function test_priceOracleUpdate() public {
        // Setup rewards
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        uint256 initialApr = rewardsOracle.getRewardsRate(address(strategy));

        // Double the reward token price from $5 to $10
        rewardTokenOracle.setPrice(10e8);

        uint256 newApr = rewardsOracle.getRewardsRate(address(strategy));

        console.log("APR with $5 price:", initialApr);
        console.log("APR with $10 price:", newApr);

        // APR should double with price doubling
        assertGt(
            newApr,
            (initialApr * 195) / 100,
            "APR didn't increase enough"
        );
        assertLt(newApr, (initialApr * 205) / 100, "APR increased too much");
    }

    function test_governanceAccess() public {
        // Try to set rewards as non-governance
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.expectRevert("!governance");
        vm.prank(user);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Should work as governance
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Try to update reward rate as non-governance
        vm.expectRevert("!governance");
        vm.prank(user);
        rewardsOracle.updateRewardRate(
            address(strategy),
            0,
            2314814814814814814
        ); // 200e18 / 86400

        // Should work as governance
        vm.prank(governance);
        rewardsOracle.updateRewardRate(
            address(strategy),
            0,
            2314814814814814814
        ); // 200e18 / 86400
    }

    function test_removeVaultRewards() public {
        // Setup rewards
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        // Verify rewards are active
        uint256 apr = rewardsOracle.getRewardsRate(address(strategy));
        assertGt(apr, 0, "APR should be positive");

        // Remove rewards
        vm.prank(governance);
        rewardsOracle.removeVaultRewards(address(strategy));

        // APR should now be 0
        apr = rewardsOracle.getRewardsRate(address(strategy));
        assertEq(apr, 0, "APR should be 0 after removing rewards");
    }

    function test_stablecoinWithoutOracle() public {
        // Test using a stablecoin without a price oracle (assumes 1:1 with USD)
        address[] memory tokens = new address[](1);
        tokens[0] = morphoToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        // Use address(0) as asset oracle to assume 1:1 USD
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(0) // No oracle, assumes $1 per token
        );

        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        uint256 aprWithoutOracle = rewardsOracle.getRewardsRate(
            address(strategy)
        );

        // Now set with an oracle at $1
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle) // Oracle at $1
        );

        uint256 aprWithOracle = rewardsOracle.getRewardsRate(address(strategy));

        console.log("APR without oracle:", aprWithoutOracle);
        console.log("APR with $1 oracle:", aprWithOracle);

        // Both should be approximately the same
        assertApproxEqRel(
            aprWithoutOracle,
            aprWithOracle,
            0.01e18,
            "APRs should be similar"
        );
    }
}
