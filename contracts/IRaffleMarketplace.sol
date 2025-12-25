// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./LibraryStruct.sol";

interface IRaffleMarketplace{
    function updateWinners(uint256 raffleId, address payable[] memory winners) external;
    function updateCurrentOngoingStage(uint256 id, RaffleLibrary.StageType stageType) external;
    function updateTicketsSold(uint256 id, RaffleLibrary.StageType stageType, uint256 ticketsSold, address rafflePlayer) external;
    function updateRaffleState(uint256 id, RaffleLibrary.RaffleState state) external;
}