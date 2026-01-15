// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library RaffleLibrary {
    /* =========================
       Enums
    ========================= */

    enum RaffleState {
        NOT_INITIALIZED,
        OPEN,
        CALCULATING,
        FINISHED,
        REVERTED
    }

    // ✅ keep the type as enum, but lets update values to match your current architecture
    enum StageType {
        PRESALE,
        SALE,
        PREMIUM
    }

    /* =========================
       Structs
    ========================= */

    // Main Raffle Structure
    struct Raffle {
        uint256 id; // Raffle No
        bool isVerifiedByMarketplace; // has that raffle been verified by the marketplace so that it can be opened
        address raffleAddress; // address of the raffle contract deployed
        RaffleCategory category; // raffle category
        string title; // title/main prize of raffle can be written here
        string description;
        uint256 raffleDuration; // how long will the raffle go on once starts
        uint256 threshold;  // if we sold x number of tickers, then the raffle ends even tho if its before the end duration
        string[] images; // ipfs uploaded uris of images of main raffle prize
        address payable[] winners; // winners of the raffle

        // country from where the prize is to be collected / delivery where the prize can be delivered
        RaffleState raffleState; // state of the raffle, init as not_initialized

        CharityInformation charityInfo; // information about charity
    }

    // Prize structure for a raffle - A raffle can have multiple prizes
    // country2: ISO 3166-1 alpha-2 (bytes2), e.g. "UA", "US", "GB"
    // Use "UN" for global/international (replaces old INT).
    struct RafflePrize {
        string prizeTitle;
        bytes2 country2;
        uint256 prizeAmount;
    }

    struct RaffleStage {
        StageType stageType;
        uint256 ticketsAvailable;
        uint256 ticketPrice;
        uint256 ticketsSold;
    }

    enum RaffleCategory {
        COLLECTIBLE,
        HOME_IMPROVEMENT,
        FASHION,
        FOOD_AND_BEVERAGES,
        HEALTH_AND_BEAUTY,
        JEWELLERY,
        MISCELLANEOUS,
        REAL_ESTATE,
        SPORTS,
        TECH,
        VEHICLES,

        FINANCE
    }

    struct Players {
        uint256 ticketPrice;
        uint256 id; // tokenId
    }

    // Information about charity if a hoster wants to donate some revenue amount to charity via charity's wallet address
    struct CharityInformation {
        string charityName;
        address payable charityAddress;
        uint256 percentToDonate;
    }

    function _shuffle(Players[] memory players) internal view returns(uint[] memory) {
        uint[] memory shuffledPlayers = new uint [](players.length);
        for (uint256 i = 0; i < players.length; i++) {
            uint256 n = uint256(keccak256(abi.encodePacked(block.timestamp))) % (players.length - i) + i;
            shuffledPlayers[i] = players[n].id;
        }
        return shuffledPlayers;
    }
}