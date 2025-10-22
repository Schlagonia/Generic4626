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
    address public morphoToken = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2; // Real MORPHO token
    address public additionalRewardToken;
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
        additionalRewardToken = tokenAddrs["LINK"]; // Additional reward token
        wethToken = tokenAddrs["WETH"];
    }

    function test_morphoRewardsCalculation() public {
        // 100 MORPHO per year for MORPHO rewards
        uint256 morphoRate = 100e18;

        // No additional rewards for this test
        address[] memory tokens = new address[](0);
        address[] memory oracles = new address[](0);
        uint256[] memory rewardRates = new uint256[](0);

        // Configure rewards as governance
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
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

        // Get the APR
        uint256 apr = rewardsOracle.getRewardsRate(address(strategy));

        console.log("MORPHO APR:", apr);
        console.log("MORPHO APR (%):", (apr * 100) / 1e18);

        // APR should be positive (MORPHO rewards via Uniswap pricing)
        assertGt(apr, 0, "APR should be positive");
        assertLt(apr, 200e18, "APR unreasonably high");
    }

    function test_morphoAndAdditionalRewards() public {
        // 100 MORPHO per year
        uint256 morphoRate = 100e18;

        // Setup additional reward token
        address[] memory tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle); // $5 per token

        // 100 tokens per day = ~1.157e15 per second
        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        // Configure rewards
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Deposit funds
        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        // Get total APR
        uint256 totalApr = rewardsOracle.getRewardsRate(address(strategy));

        // Get MORPHO APR separately
        uint256 morphoApr = rewardsOracle.getMorphoRewardsRate(
            address(strategy)
        );

        console.log("MORPHO APR:", morphoApr);
        console.log("Total APR:", totalApr);

        // Total APR should be higher than just MORPHO APR
        assertGt(
            totalApr,
            morphoApr,
            "Total APR should include additional rewards"
        );
        assertGt(morphoApr, 0, "MORPHO APR should be positive");
    }

    function test_multipleAdditionalRewardTokens() public {
        // 50 MORPHO per year
        uint256 morphoRate = 50e18;

        // Setup multiple additional reward tokens
        address[] memory tokens = new address[](2);
        tokens[0] = additionalRewardToken;
        tokens[1] = wethToken;

        address[] memory oracles = new address[](2);
        oracles[0] = address(rewardTokenOracle); // $5
        oracles[1] = address(secondRewardTokenOracle); // $2000

        uint256[] memory rewardRates = new uint256[](2);
        rewardRates[0] = 1157407407407407407; // 100 tokens per day (100e18 / 86400)
        rewardRates[1] = 11574074074074074; // 1 WETH per day (1e18 / 86400)

        // Configure rewards with MORPHO and additional tokens
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Deposit funds
        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        uint256 multiTokenApr = rewardsOracle.getRewardsRate(address(strategy));

        // Now update to only MORPHO + first additional token
        rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate, // Keep same MORPHO rate
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        uint256 singleAdditionalTokenApr = rewardsOracle.getRewardsRate(
            address(strategy)
        );

        console.log("APR with multiple additional rewards:", multiTokenApr);
        console.log(
            "APR with single additional reward:",
            singleAdditionalTokenApr
        );

        // Multiple token APR should be higher than single token
        assertGt(
            multiTokenApr,
            singleAdditionalTokenApr,
            "Multiple rewards should give higher APR"
        );
    }

    function test_zeroRewards() public {
        // Test with no rewards configured
        uint256 apr = rewardsOracle.getRewardsRate(address(strategy));
        assertEq(apr, 0, "APR should be 0 with no rewards");

        // Configure with zero MORPHO rate and zero additional rewards
        address[] memory tokens = new address[](0);
        address[] memory oracles = new address[](0);
        uint256[] memory rewardRates = new uint256[](0);

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            0, // Zero MORPHO rate
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        apr = rewardsOracle.getRewardsRate(address(strategy));
        assertEq(apr, 0, "APR should be 0 with zero reward rates");
    }

    function test_updateMorphoRate() public {
        // Initial setup with MORPHO and additional rewards
        uint256 morphoRate = 100e18;

        address[] memory tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);

        uint256 initialApr = rewardsOracle.getRewardsRate(address(strategy));

        // Double the MORPHO rate
        vm.prank(governance);
        rewardsOracle.setMorphoRate(address(strategy), 200e18);

        uint256 newApr = rewardsOracle.getRewardsRate(address(strategy));

        console.log("Initial APR:", initialApr);
        console.log("New APR after doubling MORPHO:", newApr);

        // APR should increase (but not necessarily double since we have additional rewards too)
        assertGt(newApr, initialApr, "APR should increase");
    }

    function test_priceOracleUpdate() public {
        // Setup with additional rewards (MORPHO price is from Uniswap)
        uint256 morphoRate = 50e18;

        address[] memory tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
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
        uint256 morphoRate = 100e18;
        address[] memory tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.expectRevert("!governance");
        vm.prank(user);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Should work as governance
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
            tokens,
            oracles,
            rewardRates,
            address(assetPriceOracle)
        );

        // Try to update MORPHO rate as non-governance
        vm.expectRevert("!governance");
        vm.prank(user);
        rewardsOracle.setMorphoRate(address(strategy), 200e18);

        // Should work as governance
        vm.prank(governance);
        rewardsOracle.setMorphoRate(address(strategy), 200e18);
    }

    function test_removeVaultRewards() public {
        // Setup rewards with MORPHO and additional token
        uint256 morphoRate = 100e18;

        address[] memory tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
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
        uint256 morphoRate = 50e18;

        address[] memory tokens = new address[](1);
        tokens[0] = additionalRewardToken;

        address[] memory oracles = new address[](1);
        oracles[0] = address(rewardTokenOracle);

        uint256[] memory rewardRates = new uint256[](1);
        rewardRates[0] = 1157407407407407407; // 100e18 / 86400

        // Use address(0) as asset oracle to assume 1:1 USD
        vm.prank(governance);
        rewardsOracle.setVaultRewards(
            address(strategy),
            morphoRate,
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
            morphoRate,
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
