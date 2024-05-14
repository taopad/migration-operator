// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ITpad, MigrationOperator} from "../src/MigrationOperator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {Merkle} from "@murky/src/Merkle.sol";

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
    event Claim(address indexed addr, uint256 biotAmount);

    function setUp() public {
        operator = new MigrationOperator();

        TPAD = operator.TPAD();
        BIOT = operator.BIOT();

        router = operator.router();

        sellPath.push(address(TPAD));
        sellPath.push(router.WETH());
    }

    function startMigration() private {
        operator.setLiqReceiver(liqReceiver);

        vm.prank(TPAD.operator());

        TPAD.setOperator(address(operator));
    }

    function tpadbo(address addr) private view returns (uint256) {
        return TPAD.balanceOf(addr);
    }

    function biotbo(address addr) private view returns (uint256) {
        return BIOT.balanceOf(addr);
    }

    function approve(address addr, address spender, uint256 amount) private {
        vm.prank(addr);

        TPAD.approve(spender, amount);
    }

    function sell(address addr, uint256 amount) private {
        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, sellPath, addr, block.timestamp);
    }

    function migrate(address addr) private {
        vm.prank(addr);

        operator.migrate();
    }

    function claim(address addr, uint256 biotAmount, bytes32[] memory proof) private {
        vm.prank(addr);

        operator.claim(biotAmount, proof);
    }

    function buildMerkleTree(uint256 biotAmount1, uint256 biotAmount2)
        private
        returns (bytes32, bytes32[] memory, bytes32[] memory)
    {
        Merkle m = new Merkle();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(WALLET1, biotAmount1))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(WALLET2, biotAmount2))));

        return (m.getRoot(data), m.getProof(data, 0), m.getProof(data, 1));
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

        assertEq(biotbo(address(this)), 0);
        assertEq(biotbo(address(operator)), biotBalance);

        // non owner cant adjust biot balance.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        operator.adjustTo(0);

        // owner cant adjust to a value bigger than the operator biot balance.
        vm.expectRevert("!balance");

        operator.adjustTo(biotBalance + 1);

        // owner can adjust to the exact operator biot balance (useless but working).
        operator.adjustTo(biotBalance);

        assertEq(biotbo(address(this)), 0);
        assertEq(biotbo(address(operator)), biotBalance);

        // owner can adjust to less than operator biot balance.
        operator.adjustTo(biotBalance - 10);

        assertEq(biotbo(address(this)), 10);
        assertEq(biotbo(address(operator)), biotBalance - 10);

        // owner can withdraw all the operator biot balance.
        operator.adjustTo(0);

        assertEq(biotbo(address(this)), biotBalance);
        assertEq(biotbo(address(operator)), 0);
    }

    function testSellingTpadTokensIsDisabledAfterMigrationStarted() public {
        // get two halfs of the user balance.
        uint256 tpadBalance1 = tpadbo(WALLET1);
        uint256 firstHalf = tpadBalance1 / 2;
        uint256 otherHalf = tpadBalance1 - firstHalf;

        // can sell before migration started.
        approve(WALLET1, address(router), firstHalf);

        sell(WALLET1, firstHalf);

        assertEq(tpadbo(WALLET1), otherHalf);

        // cant sell anymore after migration started.
        startMigration();

        approve(WALLET1, address(router), otherHalf);

        vm.expectRevert();

        sell(WALLET1, otherHalf);

        assertEq(tpadbo(WALLET1), otherHalf);
    }

    function testTpadTokensCanBeMigratedAfterMigrationStarted() public {
        // assert original state.
        uint256 originalLiqReceiverEth;
        uint256 tpadBalance1 = tpadbo(WALLET1);
        uint256 tpadBalance2 = tpadbo(WALLET2);

        assertGt(tpadBalance1, 0);
        assertGt(tpadBalance2, 0);
        assertGt(tpadBalance1 + tpadBalance2, 10_000 * (10 ** 18)); // ensure more than 10k can be migrated.
        assertEq(tpadbo(address(operator)), 0);
        assertFalse(operator.hasMigrated(address(WALLET1)));
        assertFalse(operator.hasMigrated(address(WALLET2)));
        assertFalse(operator.hasClaimed(address(WALLET1)));
        assertFalse(operator.hasClaimed(address(WALLET2)));

        // start the migration.
        startMigration();

        // migrate first user.
        originalLiqReceiverEth = liqReceiver.balance;

        approve(WALLET1, address(operator), tpadBalance1);

        vm.expectEmit(true, true, true, true, address(operator));

        emit Migrate(WALLET1, tpadBalance1);

        migrate(WALLET1);

        assertEq(tpadbo(WALLET1), 0);
        assertEq(tpadbo(WALLET2), tpadBalance2);
        assertEq(tpadbo(address(operator)), 0);
        assertTrue(operator.hasMigrated(WALLET1));
        assertFalse(operator.hasMigrated(WALLET2));
        assertFalse(operator.hasClaimed(address(WALLET1)));
        assertFalse(operator.hasClaimed(address(WALLET2)));
        assertGt(liqReceiver.balance, originalLiqReceiverEth);

        console.log(liqReceiver.balance - originalLiqReceiverEth);

        // migrate second user.
        originalLiqReceiverEth = liqReceiver.balance;

        approve(WALLET2, address(operator), tpadBalance2);

        vm.expectEmit(true, true, true, true, address(operator));

        emit Migrate(WALLET2, tpadBalance2);

        migrate(WALLET2);

        assertEq(tpadbo(WALLET1), 0);
        assertEq(tpadbo(WALLET2), 0);
        assertEq(tpadbo(address(operator)), 0);
        assertTrue(operator.hasMigrated(WALLET1));
        assertTrue(operator.hasMigrated(WALLET2));
        assertFalse(operator.hasClaimed(address(WALLET1)));
        assertFalse(operator.hasClaimed(address(WALLET2)));
        assertGt(liqReceiver.balance, originalLiqReceiverEth);

        console.log(liqReceiver.balance - originalLiqReceiverEth);
    }

    function testBiotTokensCanBeClaimedOnceAfterTpadTokensMigration(uint256 biotAmount1, uint256 biotAmount2) public {
        // get two random biot amount between 1 and 1M.
        biotAmount1 = bound(biotAmount1, 10 ** 18, 1_000_000 * (10 ** 18));
        biotAmount2 = bound(biotAmount2, 10 ** 18, 1_000_000 * (10 ** 18));

        assertGe(biotAmount1, 10 ** 18);
        assertGe(biotAmount2, 10 ** 18);
        assertLe(biotAmount1, 1_000_000 * (10 ** 18));
        assertLe(biotAmount2, 1_000_000 * (10 ** 18));

        // send the total biot amount to the contract.
        deal(address(BIOT), address(operator), biotAmount1 + biotAmount2);

        // assert original state.
        assertGt(tpadbo(address(WALLET1)), 0);
        assertGt(tpadbo(address(WALLET2)), 0);
        assertEq(biotbo(address(WALLET1)), 0);
        assertEq(biotbo(address(WALLET2)), 0);
        assertEq(biotbo(address(operator)), biotAmount1 + biotAmount2);
        assertFalse(operator.hasMigrated(address(WALLET1)));
        assertFalse(operator.hasMigrated(address(WALLET2)));
        assertFalse(operator.hasClaimed(address(WALLET1)));
        assertFalse(operator.hasClaimed(address(WALLET2)));

        // start the migration.
        startMigration();

        // build the merkle tree.
        (bytes32 root, bytes32[] memory proof1, bytes32[] memory proof2) = buildMerkleTree(biotAmount1, biotAmount2);

        // build another merkle tree with different values to have invalid proofs.
        (, bytes32[] memory invalidProof1, bytes32[] memory invalidProof2) =
            buildMerkleTree(biotAmount1 + 1, biotAmount2 + 1);

        // set the root.
        operator.setRoot(root);

        // users cant claim biot tokens before they migrated their tpad tokens.
        vm.expectRevert("!migrated");

        claim(WALLET1, biotAmount1, proof1);

        vm.expectRevert("!migrated");

        claim(WALLET2, biotAmount2, proof2);

        // migrate both users.
        approve(WALLET1, address(operator), tpadbo(WALLET1));
        approve(WALLET2, address(operator), tpadbo(WALLET2));

        migrate(WALLET1);
        migrate(WALLET2);

        // users cant claim with invalid biot amount and valid proof.
        vm.expectRevert("!proof");

        claim(WALLET1, biotAmount1 + 1, proof1);

        vm.expectRevert("!proof");

        claim(WALLET2, biotAmount2 + 1, proof1);

        // users cant claim with valid biot amount and invalid proof.
        vm.expectRevert("!proof");

        claim(WALLET1, biotAmount1, invalidProof1);

        vm.expectRevert("!proof");

        claim(WALLET2, biotAmount2, invalidProof2);

        // first user can claim with valid biot amount and valid proof.
        vm.expectEmit(true, true, true, true, address(operator));

        emit Claim(WALLET1, biotAmount1);

        claim(WALLET1, biotAmount1, proof1);

        assertEq(biotbo(address(WALLET1)), biotAmount1);
        assertEq(biotbo(address(WALLET2)), 0);
        assertEq(biotbo(address(operator)), biotAmount2);
        assertTrue(operator.hasClaimed(WALLET1));
        assertFalse(operator.hasClaimed(WALLET2));

        // second user can claim with valid biot amount and valid proof.
        vm.expectEmit(true, true, true, true, address(operator));

        emit Claim(WALLET2, biotAmount2);

        claim(WALLET2, biotAmount2, proof2);

        assertEq(biotbo(address(WALLET1)), biotAmount1);
        assertEq(biotbo(address(WALLET2)), biotAmount2);
        assertEq(biotbo(address(operator)), 0);
        assertTrue(operator.hasClaimed(WALLET1));
        assertTrue(operator.hasClaimed(WALLET2));

        // users cant claim twice.
        vm.expectRevert("!claimed");

        claim(WALLET1, biotAmount1, proof1);

        vm.expectRevert("!claimed");

        claim(WALLET2, biotAmount2, proof2);
    }
}
