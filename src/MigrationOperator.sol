// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

interface ITpad is IERC20 {
    function operator() external view returns (address);
    function setOperator(address) external;
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

    bytes32 public root;

    bool public migrating;

    event Migrate(address indexed addr, uint256 tpadAmount);
    event Claim(address indexed addr, uint256 biotAmount);

    constructor() Ownable(msg.sender) {
        liqReceiver = msg.sender;
    }

    function setTpadOperator(address _operator) external onlyOwner {
        TPAD.setOperator(_operator);
    }

    function setLiqReceiver(address _liqReceiver) external onlyOwner {
        require(address(0) != _liqReceiver, "!address");
        liqReceiver = _liqReceiver;
    }

    function setRoot(bytes32 _root) external onlyOwner {
        root = _root;
    }

    function adjustTo(uint256 target) external onlyOwner {
        uint256 biotBalance = BIOT.balanceOf(address(this));

        require(target <= biotBalance, "!balance");

        uint256 amount = biotBalance - target;

        if (amount == 0) return;

        BIOT.safeTransfer(msg.sender, amount);
    }

    function migrate() external {
        uint256 migratedTpad = _transferTpad(msg.sender);

        migrating = true;
        _swap();
        migrating = false;

        _transferLiq(liqReceiver);

        hasMigrated[msg.sender] = true;

        emit Migrate(msg.sender, migratedTpad);
    }

    function claim(uint256 biotAmount, bytes32[] calldata proof) external {
        require(hasMigrated[msg.sender], "!migrated");
        require(!hasClaimed[msg.sender], "!claimed");

        bool isValid = MerkleProof.verifyCalldata(
            proof, root, keccak256(bytes.concat(keccak256(abi.encode(msg.sender, biotAmount))))
        );

        if (!isValid) {
            revert("!proof");
        }

        hasClaimed[msg.sender] = true;

        BIOT.safeTransfer(msg.sender, biotAmount);

        emit Claim(msg.sender, biotAmount);
    }

    function _transferTpad(address from) private returns (uint256) {
        uint256 tpadBalance = TPAD.balanceOf(from);

        if (tpadBalance == 0) return 0;

        TPAD.safeTransferFrom(from, address(this), tpadBalance);

        return tpadBalance;
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
