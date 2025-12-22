// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "./LibraryStruct.sol";

interface IVerifier{
    struct toPassFunc {
        uint256 _raffleId;
        uint256 _durationOfRaffle;
        uint256 _threshold;
        address payable _raffleOwner;
        address _marketplceOwner;
        RaffleLibrary.RafflePrize[] _prizes;
        RaffleLibrary.RaffleStage[] _stages;
        address vrfCoordinatorV2;
        uint64 subscriptionId;
    }
    function deployRaffle(
        toPassFunc memory data
    ) external returns(address raffle);
}