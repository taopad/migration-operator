// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ITpad, MigrationOperator} from "../src/MigrationOperator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {Merkle} from "@murky/src/Merkle.sol";

contract MigrationOperatorTest is Test {
    ITpad public TPADV1;
    IERC20 public TPADV2;
    IUniswapV2Router02 public router;
    MigrationOperator public moperator;
    address[] public sellPath;

    address liqReceiver = address(1);

    // wallets with taopad.
    address public constant WALLET1 = 0xaA11cF08664deC11717D622eb248284C222fc0d8;
    address public constant WALLET2 = 0x28f6AE4cEC9864cb85aCE4a28101567BD7Ba3ec2;

    event Migrate(address indexed addr, uint256 tpadV1Amount);
    event Claim(address indexed addr, uint256 tpadV2Amount);

    function setUp() public {
        moperator = new MigrationOperator();

        TPADV1 = moperator.TPADV1();
        TPADV2 = moperator.TPADV2();

        router = moperator.router();

        sellPath.push(address(TPADV1));
        sellPath.push(router.WETH());
    }

    function startMigration() private {
        moperator.setLiqReceiver(liqReceiver);

        vm.prank(TPADV1.operator());

        TPADV1.setOperator(address(moperator));
    }

    function tpadV1bo(address addr) private view returns (uint256) {
        return TPADV1.balanceOf(addr);
    }

    function tpadV2bo(address addr) private view returns (uint256) {
        return TPADV2.balanceOf(addr);
    }

    function approve(address addr, address spender, uint256 tpadV1amount) private {
        vm.prank(addr);

        TPADV1.approve(spender, tpadV1amount);
    }

    function sell(address addr, uint256 tpadV2amount) private {
        vm.prank(addr);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tpadV2amount, 0, sellPath, addr, block.timestamp);
    }

    function migrate(address addr) private {
        vm.prank(addr);

        moperator.migrate();
    }

    function claim(address addr, uint256 tpadV2Amount, bytes32[] memory proof) private {
        vm.prank(addr);

        moperator.claim(tpadV2Amount, proof);
    }

    function buildMerkleTree(uint256 tpadV2Amount1, uint256 tpadV2Amount2)
        private
        returns (bytes32, bytes32[] memory, bytes32[] memory)
    {
        Merkle m = new Merkle();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(WALLET1, tpadV2Amount1))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(WALLET2, tpadV2Amount2))));

        return (m.getRoot(data), m.getProof(data, 0), m.getProof(data, 1));
    }

    function testDefaultOwner() public view {
        assertEq(moperator.owner(), address(this));
    }

    function testDefaultLiqReceiver() public view {
        assertEq(moperator.liqReceiver(), address(this));
    }

    function testOwnerCanSetTpadOperator(address newOperator) public {
        vm.assume(address(0) != newOperator);

        // non owner cant set taopad operator.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        moperator.setTpadOperator(newOperator);

        // taopad operator must be the migration operator first.
        vm.expectRevert("!operator");

        moperator.setTpadOperator(newOperator);

        // set migration operator as taopad operator.
        startMigration();

        // owner cant set taopad operator to 0x0.
        vm.expectRevert("!address");

        moperator.setTpadOperator(address(0));

        // owner can set taopad operator to any non zero address.
        moperator.setTpadOperator(newOperator);

        assertEq(TPADV1.operator(), newOperator);
    }

    function testOwnerCanSetLiqReceiver(address newLiqReceiver) public {
        vm.assume(address(0) != newLiqReceiver);

        // non owner cant set liq receiver.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        moperator.setLiqReceiver(newLiqReceiver);

        // owner cant set liq receiver to 0x0.
        vm.expectRevert("!address");

        moperator.setLiqReceiver(address(0));

        // owner can set liq receiver to any non zero address.
        moperator.setLiqReceiver(newLiqReceiver);

        assertEq(moperator.liqReceiver(), newLiqReceiver);
    }

    function testOwnerCanSetRoot(bytes32 root) public {
        // by default the root is 0x0.
        assertEq(moperator.root(), bytes32(0));

        // non owner cant set root.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        moperator.setRoot(root);

        // owner can set root.
        moperator.setRoot(root);

        assertEq(moperator.root(), root);
    }

    function testOwnerCanAdjustTpadV2BalanceTo(uint256 tpadV2Balance) public {
        // get a random tpad v2 balance between 1 and 10M biot.
        tpadV2Balance = bound(tpadV2Balance, 10 ** 18, 10_000_000 * (10 ** 18));

        assertGe(tpadV2Balance, 10 ** 18);
        assertLe(tpadV2Balance, 10_000_000 * (10 ** 18));

        // send it to the migration operator.
        deal(address(TPADV2), address(moperator), tpadV2Balance);

        assertEq(tpadV2bo(address(this)), 0);
        assertEq(tpadV2bo(address(moperator)), tpadV2Balance);

        // non owner cant adjust tpad v2 balance.
        vm.prank(address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        moperator.adjustTo(0);

        // owner cant adjust to a value bigger than the operator tpad v2 balance.
        vm.expectRevert("!balance");

        moperator.adjustTo(tpadV2Balance + 1);

        // owner can adjust to the exact operator tpad v2 balance (useless but working).
        moperator.adjustTo(tpadV2Balance);

        assertEq(tpadV2bo(address(this)), 0);
        assertEq(tpadV2bo(address(moperator)), tpadV2Balance);

        // owner can adjust to less than operator tpad v2 balance.
        moperator.adjustTo(tpadV2Balance - 10);

        assertEq(tpadV2bo(address(this)), 10);
        assertEq(tpadV2bo(address(moperator)), tpadV2Balance - 10);

        // owner can withdraw all the operator tpad v2 balance.
        moperator.adjustTo(0);

        assertEq(tpadV2bo(address(this)), tpadV2Balance);
        assertEq(tpadV2bo(address(moperator)), 0);
    }

    function testSellingTpadTokensIsDisabledAfterMigrationStarted() public {
        // get two halfs of the user balance.
        uint256 tpadV1Balance1 = tpadV1bo(WALLET1);
        uint256 firstHalf = tpadV1Balance1 / 2;
        uint256 otherHalf = tpadV1Balance1 - firstHalf;

        // can sell before migration started.
        approve(WALLET1, address(router), firstHalf);

        sell(WALLET1, firstHalf);

        assertEq(tpadV1bo(WALLET1), otherHalf);

        // cant sell anymore after migration started.
        startMigration();

        approve(WALLET1, address(router), otherHalf);

        vm.expectRevert();

        sell(WALLET1, otherHalf);

        assertEq(tpadV1bo(WALLET1), otherHalf);
    }

    function testTpadTokensCanBeMigratedAfterMigrationStarted() public {
        // assert original state.
        uint256 originalLiqReceiverEth;
        uint256 tpadV1Balance1 = tpadV1bo(WALLET1);
        uint256 tpadV1Balance2 = tpadV1bo(WALLET2);

        assertGt(tpadV1Balance1, 0);
        assertGt(tpadV1Balance2, 0);
        assertGt(tpadV1Balance1 + tpadV1Balance2, 10_000 * (10 ** 18)); // ensure more than 10k can be migrated.
        assertEq(tpadV1bo(address(moperator)), 0);
        assertFalse(moperator.hasMigrated(address(WALLET1)));
        assertFalse(moperator.hasMigrated(address(WALLET2)));
        assertFalse(moperator.hasClaimed(address(WALLET1)));
        assertFalse(moperator.hasClaimed(address(WALLET2)));

        // start the migration.
        startMigration();

        // migrate first user.
        originalLiqReceiverEth = liqReceiver.balance;

        approve(WALLET1, address(moperator), tpadV1Balance1);

        vm.expectEmit(true, true, true, true, address(moperator));

        emit Migrate(WALLET1, tpadV1Balance1);

        migrate(WALLET1);

        assertEq(tpadV1bo(WALLET1), 0);
        assertEq(tpadV1bo(WALLET2), tpadV1Balance2);
        assertEq(tpadV1bo(address(moperator)), 0);
        assertTrue(moperator.hasMigrated(WALLET1));
        assertFalse(moperator.hasMigrated(WALLET2));
        assertFalse(moperator.hasClaimed(address(WALLET1)));
        assertFalse(moperator.hasClaimed(address(WALLET2)));
        assertGt(liqReceiver.balance, originalLiqReceiverEth);

        console.log(liqReceiver.balance - originalLiqReceiverEth);

        // migrate second user.
        originalLiqReceiverEth = liqReceiver.balance;

        approve(WALLET2, address(moperator), tpadV1Balance2);

        vm.expectEmit(true, true, true, true, address(moperator));

        emit Migrate(WALLET2, tpadV1Balance2);

        migrate(WALLET2);

        assertEq(tpadV1bo(WALLET1), 0);
        assertEq(tpadV1bo(WALLET2), 0);
        assertEq(tpadV1bo(address(moperator)), 0);
        assertTrue(moperator.hasMigrated(WALLET1));
        assertTrue(moperator.hasMigrated(WALLET2));
        assertFalse(moperator.hasClaimed(address(WALLET1)));
        assertFalse(moperator.hasClaimed(address(WALLET2)));
        assertGt(liqReceiver.balance, originalLiqReceiverEth);

        console.log(liqReceiver.balance - originalLiqReceiverEth);
    }

    function testBiotTokensCanBeClaimedOnceAfterTpadTokensMigration(uint256 tpadV2Amount1, uint256 tpadV2Amount2)
        public
    {
        // get two random tpad V2 amount between 1 and 1M.
        tpadV2Amount1 = bound(tpadV2Amount1, 10 ** 18, 1_000_000 * (10 ** 18));
        tpadV2Amount2 = bound(tpadV2Amount2, 10 ** 18, 1_000_000 * (10 ** 18));

        assertGe(tpadV2Amount1, 10 ** 18);
        assertGe(tpadV2Amount2, 10 ** 18);
        assertLe(tpadV2Amount1, 1_000_000 * (10 ** 18));
        assertLe(tpadV2Amount2, 1_000_000 * (10 ** 18));

        // send the total tpad V2 amount to the contract.
        deal(address(TPADV2), address(moperator), tpadV2Amount1 + tpadV2Amount2);

        // assert original state.
        assertGt(tpadV1bo(address(WALLET1)), 0);
        assertGt(tpadV1bo(address(WALLET2)), 0);
        assertEq(tpadV2bo(address(WALLET1)), 0);
        assertEq(tpadV2bo(address(WALLET2)), 0);
        assertEq(tpadV2bo(address(moperator)), tpadV2Amount1 + tpadV2Amount2);
        assertFalse(moperator.hasMigrated(address(WALLET1)));
        assertFalse(moperator.hasMigrated(address(WALLET2)));
        assertFalse(moperator.hasClaimed(address(WALLET1)));
        assertFalse(moperator.hasClaimed(address(WALLET2)));

        // start the migration.
        startMigration();

        // build the merkle tree.
        (bytes32 root, bytes32[] memory proof1, bytes32[] memory proof2) = buildMerkleTree(tpadV2Amount1, tpadV2Amount2);

        // build another merkle tree with different values to have invalid proofs.
        (, bytes32[] memory invalidProof1, bytes32[] memory invalidProof2) =
            buildMerkleTree(tpadV2Amount1 + 1, tpadV2Amount2 + 1);

        // set the root.
        moperator.setRoot(root);

        // users cant claim biot tokens before they migrated their tpad V1 tokens.
        vm.expectRevert("!migrated");

        claim(WALLET1, tpadV2Amount1, proof1);

        vm.expectRevert("!migrated");

        claim(WALLET2, tpadV2Amount2, proof2);

        // migrate both users.
        approve(WALLET1, address(moperator), tpadV1bo(WALLET1));
        approve(WALLET2, address(moperator), tpadV1bo(WALLET2));

        migrate(WALLET1);
        migrate(WALLET2);

        // users cant claim with invalid tpad V2 amount and valid proof.
        vm.expectRevert("!proof");

        claim(WALLET1, tpadV2Amount1 + 1, proof1);

        vm.expectRevert("!proof");

        claim(WALLET2, tpadV2Amount2 + 1, proof2);

        // users cant claim with valid tpad V2 amount and invalid proof.
        vm.expectRevert("!proof");

        claim(WALLET1, tpadV2Amount1, invalidProof1);

        vm.expectRevert("!proof");

        claim(WALLET2, tpadV2Amount2, invalidProof2);

        // first user can claim with valid tpad V2 amount and valid proof.
        vm.expectEmit(true, true, true, true, address(moperator));

        emit Claim(WALLET1, tpadV2Amount1);

        claim(WALLET1, tpadV2Amount1, proof1);

        assertEq(tpadV2bo(address(WALLET1)), tpadV2Amount1);
        assertEq(tpadV2bo(address(WALLET2)), 0);
        assertEq(tpadV2bo(address(moperator)), tpadV2Amount2);
        assertTrue(moperator.hasClaimed(WALLET1));
        assertFalse(moperator.hasClaimed(WALLET2));

        // second user can claim with valid tpad V2 amount and valid proof.
        vm.expectEmit(true, true, true, true, address(moperator));

        emit Claim(WALLET2, tpadV2Amount2);

        claim(WALLET2, tpadV2Amount2, proof2);

        assertEq(tpadV2bo(address(WALLET1)), tpadV2Amount1);
        assertEq(tpadV2bo(address(WALLET2)), tpadV2Amount2);
        assertEq(tpadV2bo(address(moperator)), 0);
        assertTrue(moperator.hasClaimed(WALLET1));
        assertTrue(moperator.hasClaimed(WALLET2));

        // users cant claim twice.
        vm.expectRevert("!claimed");

        claim(WALLET1, tpadV2Amount1, proof1);

        vm.expectRevert("!claimed");

        claim(WALLET2, tpadV2Amount2, proof2);
    }
}
