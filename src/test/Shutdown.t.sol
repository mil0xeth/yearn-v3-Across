pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        vm.prank(management);
        strategy.emergencyWithdraw(_amount);

        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Make sure we can still withdraw the full amount
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

    function test_shutdownMaxWithdraw() public {
        uint256 _amount = maxFuzzAmount;
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(100 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Make sure we can still withdraw the full amount
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
