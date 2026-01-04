// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC2771Recipient} from "@opengsn/contracts/src/ERC2771Recipient.sol";

contract RMT is ERC20, Ownable, ERC2771Recipient {
    error InsufficientPayment();
    error SoldOut();
    error PremintAlreadyDone();
    error RefundFailed();
    error WithdrawFailed();

    uint256 private constant WAD = 1e18;

    uint256 public constant PRICE_WEI_PER_TOKEN = 0.0001 ether;
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * WAD;

    bool private preminted;

    event TokensPurchased(address indexed buyer, uint256 weiIn, uint256 tokensOut, uint256 refundWei);
    event Preminted(address indexed owner, uint256 tokensOut);
    event Withdrawn(address indexed owner, uint256 amountWei);

    constructor(address trustedForwarder_) ERC20("RMT", "RMT") {
        _setTrustedForwarder(trustedForwarder_);
    }

    function price() external pure returns (uint256) {
        return PRICE_WEI_PER_TOKEN;
    }

    function premint10Percent() external onlyOwner {
        if (preminted) revert PremintAlreadyDone();
        preminted = true;

        uint256 amount = MAX_SUPPLY / 10;
        _mint(owner(), amount);
        emit Preminted(owner(), amount);
    }

    function buyTokens() public payable {
        uint256 p = PRICE_WEI_PER_TOKEN;
        uint256 v = msg.value;
        if (v < p) revert InsufficientPayment();

        uint256 whole = v / p;
        uint256 tokensOut = whole * WAD;

        uint256 supply = totalSupply();
        if (supply + tokensOut > MAX_SUPPLY) revert SoldOut();

        uint256 cost = whole * p;
        uint256 refund = v - cost;

        address buyer = _msgSender();
        _mint(buyer, tokensOut);

        if (refund != 0) {
            (bool ok, ) = payable(buyer).call{value: refund}("");
            if (!ok) revert RefundFailed();
        }

        emit TokensPurchased(buyer, v, tokensOut, refund);
    }

    receive() external payable {
        buyTokens();
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert WithdrawFailed();
        emit Withdrawn(owner(), bal);
    }

    function _msgSender()
        internal
        view
        override(Context, ERC2771Recipient)
        returns (address ret)
    {
        return ERC2771Recipient._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Recipient)
        returns (bytes calldata ret)
    {
        return ERC2771Recipient._msgData();
    }
}