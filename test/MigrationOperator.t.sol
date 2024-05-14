// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ITpad, MigrationOperator} from "../src/MigrationOperator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract MigrationOperatorTest is Test {
    ITpad public TPAD;
    IERC20 public BIOT;
    IUniswapV2Router02 public router;
    MigrationOperator public operator;
    address[] public sellPath;

    address liqReceiver = address(1);

    // wallets with taopad.
    address public constant WALLET1 = 0xaA11cF08664deC11717D622eb248284C222fc0d8;
    address public constant WALLET2 = 0x28f6AE4cEC9864cb85aCE4a28101567BD7Ba3ec2;

    event Migrate(address indexed addr, uint256 tpadAmount);

    function setUp() public {
        operator = new MigrationOperator();

        TPAD = operator.TPAD();
        BIOT = operator.BIOT();

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

    function testOwnerCanSetTpadOperator(address newOperator) public {
        vm.assume(address(0) != newOperator);

        // non owner cant set taopad operator.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        operator.setTpadOperator(newOperator);

        // taopad operator must be the migration operator first.
        vm.expectRevert("!operator");

        operator.setTpadOperator(newOperator);

        // set migration operator as taopad operator.
        startMigration();

        // owner cant set taopad operator to 0x0.
        vm.expectRevert("!address");

        operator.setTpadOperator(address(0));

        // owner can set taopad operator to any non zero address.
        operator.setTpadOperator(newOperator);

        assertEq(TPAD.operator(), newOperator);
    }

    function testOwnerCanSetLiqReceiver(address newLiqReceiver) public {
        vm.assume(address(0) != newLiqReceiver);

        // by default the liq receiver is the deployer.
        assertEq(operator.liqReceiver(), address(this));

        // non owner cant set liq receiver.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        operator.setLiqReceiver(newLiqReceiver);

        // owner cant set liq receiver to 0x0.
        vm.expectRevert("!address");

        operator.setLiqReceiver(address(0));

        // owner can set liq receiver to any non zero address.
        operator.setLiqReceiver(newLiqReceiver);

        assertEq(operator.liqReceiver(), newLiqReceiver);
    }

    function testOwnerCanSetRoot(bytes32 root) public {
        // by default the root is 0x0.
        assertEq(operator.root(), bytes32(0));

        // non owner cant set root.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        operator.setRoot(root);

        // owner can set root.
        operator.setRoot(root);

        assertEq(operator.root(), root);
    }

    function testOwnerCanAdjustBiotBalanceTo(uint256 biotBalance) public {
        // get a random biot balance between 1 and 10M biot.
        biotBalance = bound(biotBalance, 10 ** 18, 10_000_000 * (10 ** 18));

        assertGe(biotBalance, 10 ** 18);
        assertLe(biotBalance, 10_000_000 * (10 ** 18));

        // send it to the migration operator.
        deal(address(BIOT), address(operator), biotBalance);

        assertEq(BIOT.balanceOf(address(this)), 0);
        assertEq(BIOT.balanceOf(address(operator)), biotBalance);

        // non owner cant adjust biot balance.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        operator.adjustTo(0);

        // owner cant adjust to a value bigger than the operator biot balance.
        vm.expectRevert("!balance");

        operator.adjustTo(biotBalance + 1);

        // owner can adjust to the exact operator biot balance (useless but working).
        operator.adjustTo(biotBalance);

        assertEq(BIOT.balanceOf(address(this)), 0);
        assertEq(BIOT.balanceOf(address(operator)), biotBalance);

        // owner can adjust to less than operator biot balance.
        operator.adjustTo(biotBalance - 10);

        assertEq(BIOT.balanceOf(address(this)), 10);
        assertEq(BIOT.balanceOf(address(operator)), biotBalance - 10);

        // owner can withdraw all the operator biot balance.
        operator.adjustTo(0);

        assertEq(BIOT.balanceOf(address(this)), biotBalance);
        assertEq(BIOT.balanceOf(address(operator)), 0);
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

        vm.expectEmit(true, true, true, true, address(operator));
        emit Migrate(WALLET1, balance1);
        migrate(WALLET1);

        vm.expectEmit(true, true, true, true, address(operator));
        emit Migrate(WALLET2, balance2);
        migrate(WALLET2);

        assertEq(bo(WALLET1), 0);
        assertEq(bo(WALLET2), 0);
        assertTrue(operator.hasMigrated(WALLET1));
        assertTrue(operator.hasMigrated(WALLET2));

        assertGt(liqReceiver.balance, originalLiqReceiverEth);

        console.log(liqReceiver.balance - originalLiqReceiverEth);
    }
}
