// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ITpad, MigrationOperator} from "../src/MigrationOperator.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract MigrationOperatorTest is Test {
    ITpad public TPAD;
    IUniswapV2Router02 public router;
    MigrationOperator public operator;
    address[] public sellPath;

    address liqReceiver = address(1);

    // wallets with taopad.
    address public constant WALLET1 = 0xaA11cF08664deC11717D622eb248284C222fc0d8;
    address public constant WALLET2 = 0x28f6AE4cEC9864cb85aCE4a28101567BD7Ba3ec2;

    function setUp() public {
        operator = new MigrationOperator();

        TPAD = operator.TPAD();

        router = operator.router();

        sellPath.push(address(TPAD));
        sellPath.push(router.WETH());
    }

    function startMigration() internal {
        operator.setLiqReceiver(liqReceiver);

        vm.prank(TPAD.operator());

        TPAD.setOperator(address(operator));
    }

    function bo(address addr) internal view returns (uint256) {
        return TPAD.balanceOf(addr);
    }

    function approve(address addr, address spender, uint256 amount) internal {
        vm.prank(addr);

        TPAD.approve(spender, amount);
    }

    function sell(address addr, uint256 amount) internal {
        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, sellPath, addr, block.timestamp);
    }

    function migrate(address addr) internal {
        vm.prank(addr);

        operator.migrate();
    }

    function testDefaultOwner() public view {
        assertEq(operator.owner(), address(this));
    }

    function testDefaultLiqReceiver() public view {
        assertEq(operator.liqReceiver(), address(this));
    }

    function testCanSetTpadOperator(address newOperator) public {
        vm.assume(address(0) != newOperator);

        // set taopad operator as the migration operator.
        startMigration();

        assertEq(TPAD.operator(), address(operator));

        // cant set operator to 0x0.
        vm.expectRevert("!address");

        operator.setTpadOperator(address(0));

        // can set operator to any other address.
        operator.setTpadOperator(newOperator);

        assertEq(TPAD.operator(), newOperator);
    }

    function testSellingIsDisabledAfterMigrationStarted() public {
        // get two halfs of the balance.
        uint256 balance1 = bo(WALLET1);
        uint256 firstHalf = balance1 / 2;
        uint256 otherHalf = balance1 - firstHalf;

        // can sell before migration started.
        approve(WALLET1, address(router), firstHalf);

        sell(WALLET1, firstHalf);

        assertEq(bo(WALLET1), otherHalf);

        // cant sell anymore after migration started.
        startMigration();

        approve(WALLET1, address(router), otherHalf);

        vm.expectRevert();

        sell(WALLET1, otherHalf);

        assertEq(bo(WALLET1), otherHalf);
    }

    function testTokensCanBeMigratedAfterMigrationStarted() public {
        // test current state.
        uint256 balance1 = bo(WALLET1);
        uint256 balance2 = bo(WALLET2);
        uint256 originalLiqReceiverEth = liqReceiver.balance;

        assertGt(balance1, 0);
        assertGt(balance2, 0);
        assertGt(balance1 + balance2, 10_000 * (10 ** 18)); // ensure more than 10k can be migrated.
        assertFalse(operator.hasMigrated(WALLET1));
        assertFalse(operator.hasMigrated(WALLET2));

        // migrate both wallets.
        startMigration();

        approve(WALLET1, address(operator), balance1);
        approve(WALLET2, address(operator), balance2);

        migrate(WALLET1);
        migrate(WALLET2);

        assertEq(bo(WALLET1), 0);
        assertEq(bo(WALLET2), 0);
        assertTrue(operator.hasMigrated(WALLET1));
        assertTrue(operator.hasMigrated(WALLET2));

        assertGt(liqReceiver.balance, originalLiqReceiverEth);

        console.log(liqReceiver.balance - originalLiqReceiverEth);
    }
}
