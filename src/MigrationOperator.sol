// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ITpad is IERC20 {
    function operator() external view returns (address);
    function setOparator(address) external;
}

contract MigrationOperator is Ownable {
    using SafeERC20 for ITpad;

    ITpad public constant TPAD = ITpad(0x5483DC6abDA5F094865120B2D251b5744fc2ECB5);

    address public liqReceiver;

    bool public migrating;

    constructor() Ownable(msg.sender) {
        liqReceiver = msg.sender;
    }

    function setOperator(address _operator) external onlyOwner {
        TPAD.setOparator(_operator);
    }

    function selLiqReceiver(address _liqReceiver) external onlyOwner {
        liqReceiver = _liqReceiver;
    }

    function migrate() external {
        // transfer all sender taopad to this contract.
        _transferTpad(msg.sender);

        // wrap swap inside migrating switch.
        migrating = true;
        _swap();
        migrating = false;

        // transfer all the ether to liqReceiver.
        _transferLiq(liqReceiver);
    }

    function _transferTpad(address from) private {
        uint256 tpadBalance = TPAD.balanceOf(from);

        if (tpadBalance == 0) return;

        TPAD.safeTransferFrom(from, address(this), tpadBalance);
    }

    function _transferLiq(address to) private {
        uint256 ethBalance = address(this).balance;

        if (ethBalance == 0) return;

        (bool sent,) = payable(to).call{value: ethBalance}("");
        require(sent, "Failed to send Ether");
    }

    function _swap() private {}

    fallback() external payable {
        require(migrating);
    }

    receive() external payable {
        require(migrating);
    }
}
