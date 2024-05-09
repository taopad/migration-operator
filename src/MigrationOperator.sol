// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

interface ITpad is IERC20 {
    function operator() external view returns (address);
    function setOparator(address) external;
}

contract MigrationOperator is Ownable {
    using SafeERC20 for ITpad;
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    ITpad public constant TPAD = ITpad(0x5483DC6abDA5F094865120B2D251b5744fc2ECB5);
    IERC20 public constant BIOT = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984); // UNI token address for now

    mapping(address => bool) public hasMigrated;
    mapping(address => bool) public hasClaimed;

    address public liqReceiver;

    bool public migrating;

    constructor() Ownable(msg.sender) {
        liqReceiver = msg.sender;
    }

    function setTpadOperator(address _operator) external onlyOwner {
        TPAD.setOparator(_operator);
    }

    function setLiqReceiver(address _liqReceiver) external onlyOwner {
        liqReceiver = _liqReceiver;
    }

    function skim() external onlyOwner {
        uint256 biotBalance = BIOT.balanceOf(address(this));

        BIOT.safeTransfer(msg.sender, biotBalance);
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

        // record the sender has migrated.
        hasMigrated[msg.sender] = true;
    }

    function claim(uint256 amount) external {
        require(hasMigrated[msg.sender], "Sender has not migrated");
        require(!hasClaimed[msg.sender], "Sender has already claimed");

        hasClaimed[msg.sender] = true;

        BIOT.safeTransfer(msg.sender, amount);
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

    function _swap() private {
        uint256 amountIn = TPAD.balanceOf(address(this));

        if (amountIn == 0) return;

        TPAD.approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(TPAD);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(this), block.timestamp);
    }

    fallback() external payable {
        require(migrating);
    }

    receive() external payable {
        require(migrating);
    }
}
