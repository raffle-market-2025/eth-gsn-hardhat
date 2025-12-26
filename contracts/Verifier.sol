// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IVerifier.sol";
import "./Raffle.sol";

contract Verifier is IVerifier {
    address public marketplace;
    address public owner;

    constructor() {
        owner = msg.sender;
        marketplace = msg.sender;
    }

    function setMarketplace(address _marketplace) external onlyOwner {
        marketplace = _marketplace;
    }

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function deployRaffle(toPassFunc memory data)
        external
        onlyMarketplace
        returns (address raffle)
    {
        // NOTE: RaffleContract constructor expects 8 args in your current Raffle.sol
        RaffleContract raffleDeployed = new RaffleContract(
            data._raffleId,
            data._durationOfRaffle,
            data._threshold,
            data._raffleOwner,
            data._marketplceOwner,
            data._prizes,
            data._stages,
            marketplace
        );

        raffle = address(raffleDeployed);
    }

    modifier onlyMarketplace() {
        require(msg.sender == marketplace, "No access");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only Owner is allowed");
        _;
    }
}