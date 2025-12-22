// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library RaffleLibrary {
    struct RaffleStage {
        StageType stageType;    
        uint256 ticketsAvailable;
        uint256 ticketPrice;
        uint256 ticketsSold;
    }

    enum StageType{
        PRESALE,
        SALE,
        PREMIUM
    }

     enum RaffleState {
        NOT_INITIALIZED,
        OPEN,
        CALCULATING,
        FINISHED,
        REVERTED
    }

    enum RaffleCategory {
        COLLECTIBLE,
        HOME_IMPROVEMENT,
        FASHION,
        FOOD_AND_BEVERAGES,
        HEALTH_AND_BEAUTY,
        JEWELLERY,
        MISCELLANEOUS,
        REALTY,
        SPORTS,
        TECH,
        VEHICLES,

        FINANCE
    }

    // The countries which are supported for delivering/collecting the prize
    enum PrizeCollectionCountry {
        UA,
        UK,
        PL,
        IT,
        EU,
        CA,
        US,

        INT
    }

    // Prize structure for a raffle - A raffle can have multiple prizes
    struct RafflePrize {
        string prizeTitle;
        PrizeCollectionCountry country;
        uint256 prizeAmount;
    }

    // Information about charity if a hoster wants to donate some revenue amount to charity via charity's wallet address
    struct CharityInformation {
        string charityName;
        address payable charityAddress;
        uint256 percentToDonate;
    }

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
        CharityInformation charityInfo; // information about charity
        address payable[] winners; // winners of the raffle
        // country from where the prize is to be collected / delivery where the prize can be delivered
        RaffleState raffleState; // state of the raffle, init as not_initialized
    }

    // ticket price and id of nft
    struct Players {
        uint256 ticketPrice;
        uint id;
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
