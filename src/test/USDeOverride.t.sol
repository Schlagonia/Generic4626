// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";
import {StakedUSDe} from "../Strategies/Ethena/StakedUSDe.sol";

import {AuctionFactory, Auction} from "@periphery/Auctions/AuctionFactory.sol";
import {IAuctionSwapper} from "@periphery/swappers/interfaces/IAuctionSwapper.sol";

import {IsUSDe} from "../interfaces/IsUSDe.sol";

interface IStakedUSDe is IAuctionSwapper {
    function setAuction(address _auction) external;
    function startCooldown(uint256 _assetAmount) external returns (uint256);
    function cooldownAll() external returns (uint256);
    function unstake() external;
}

contract CooldownTests is Setup {
    uint256 public cooldown;

    function setUp() public virtual override {
        super.setUp();

        // sUSDe vault
        vault = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpStakedUSDe());

        cooldown = IsUSDe(vault).cooldownDuration();
    }

    function setUpStakedUSDe() public returns (address) {
        vm.startPrank(management);
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(new StakedUSDe())
        );

        _strategy.setKeeper(keeper);

        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        vm.stopPrank();

        return address(_strategy);
    }

    function test_operationWithCooldown(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Cannot Withdraw funds before cooldown
        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Start cooldown
        vm.prank(management);
        IStakedUSDe(address(strategy)).startCooldown(_amount + profit);

        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        skip(cooldown);

        console.log("Max Redeem ", strategy.maxRedeem(user));

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operationWithCooldown_half(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Cannot Withdraw funds before cooldown
        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(user);
        strategy.redeem(_amount / 2, user, user);

        // Start cooldown
        vm.prank(management);
        IStakedUSDe(address(strategy)).startCooldown((_amount + profit) / 2);

        skip(cooldown);

        vm.prank(user);
        strategy.redeem(_amount / 2, user, user);

        assertGt(
            asset.balanceOf(user),
            balanceBefore + (_amount / 2),
            "!final balance"
        );
    }

    function test_reportDuringCooldown(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Start cooldown for everything
        vm.prank(management);
        IStakedUSDe(address(strategy)).cooldownAll();

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        skip(cooldown);

        vm.prank(management);
        IStakedUSDe(address(strategy)).unstake();

        // Should have no profit since it was cooling down
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        // Check return Values
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_emergencyWithdraw_cools(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        vm.prank(management);
        strategy.emergencyWithdraw(2 ** 256 - 1);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // All funds should be cooling down
        assertEq(strategy.balanceOfVault(), 0);

        skip(cooldown);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
    }
}

contract USDeOperationTest is OperationTest {
    function setUp() public virtual override {
        super.setUp();

        // sUSDe vault
        vault = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpStakedUSDe());

        // Use 0 cooldown for normal tests
        vm.prank(0x3B0AAf6e6fCd4a7cEEf8c92C32DFeA9E64dC1862);
        IsUSDe(vault).setCooldownDuration(0);
    }

    function setUpStakedUSDe() public returns (address) {
        vm.startPrank(management);
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(new StakedUSDe())
        );

        _strategy.setKeeper(keeper);

        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        vm.stopPrank();

        return address(_strategy);
    }

    function test_auctionSwaps(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > 1e18 && _amount < maxFuzzAmount);
        _profitFactor = uint16(
            bound(uint256(_profitFactor), 10, MAX_BPS - 100)
        );

        // Deploy an auction contract
        address _auction = AuctionFactory(
            IStakedUSDe(address(strategy)).auctionFactory()
        ).createNewAuction(address(asset), address(strategy), management);

        // Use kickable and kick hooks.
        vm.prank(management);
        Auction(_auction).setHookFlags(true, true, false, false);

        address rewardToken = tokenAddrs["USDC"];
        address buyer = address(123);

        // Enable the auction
        vm.prank(management);
        bytes32 _id = Auction(_auction).enable(rewardToken, address(strategy));

        // Auction must have asset as want.
        address _badAuction = AuctionFactory(
            IStakedUSDe(address(strategy)).auctionFactory()
        ).createNewAuction(address(rewardToken), address(strategy), management);
        vm.expectRevert("wrong want");
        vm.prank(management);
        IStakedUSDe(address(strategy)).setAuction(_badAuction);

        // Set the auction contract.
        vm.prank(management);
        IStakedUSDe(address(strategy)).setAuction(_auction);

        vm.expectRevert("!allowed");
        vm.prank(_auction);
        IStakedUSDe(address(strategy)).auctionKicked(address(asset));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Earn Interest
        skip(1 days);

        // Simulate merkle airdrop
        // Scale from crv usd decimals down to usdc
        uint256 toDrop = (_amount * _profitFactor) / MAX_BPS / 1e12;

        assertEq(Auction(_auction).kickable(_id), 0);
        vm.expectRevert("nothing to kick");
        Auction(_auction).kick(_id);

        airdrop(ERC20(rewardToken), address(strategy), toDrop);

        assertEq(Auction(_auction).kickable(_id), toDrop);
        assertEq(Auction(_auction).kick(_id), toDrop);

        skip(Auction(_auction).auctionLength() / 2);

        uint256 amountNeeded = Auction(_auction).getAmountNeeded(_id, toDrop);
        assertGt(amountNeeded, 1);

        airdrop(asset, buyer, amountNeeded);

        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(ERC20(rewardToken).balanceOf(address(strategy)), 0);

        // Take auction
        vm.prank(buyer);
        asset.approve(_auction, amountNeeded);

        vm.prank(buyer);
        Auction(_auction).take(_id);

        assertEq(asset.balanceOf(address(strategy)), amountNeeded);
        assertEq(ERC20(rewardToken).balanceOf(address(strategy)), 0);

        vm.prank(management);
        strategy.setDoHealthCheck(false);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Doesnt reinvest profits
        assertEq(asset.balanceOf(address(strategy)), amountNeeded);

        // Check return Values
        assertGe(profit, amountNeeded, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}

contract USDeShutdownTest is ShutdownTest {
    function setUp() public virtual override {
        super.setUp();

        // vault
        vault = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpStakedUSDe());

        // Use 0 cooldown for normal tests
        vm.prank(0x3B0AAf6e6fCd4a7cEEf8c92C32DFeA9E64dC1862);
        IsUSDe(vault).setCooldownDuration(0);
    }

    function setUpStakedUSDe() public returns (address) {
        vm.startPrank(management);
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(new StakedUSDe())
        );

        _strategy.setKeeper(keeper);

        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        vm.stopPrank();

        return address(_strategy);
    }
}
