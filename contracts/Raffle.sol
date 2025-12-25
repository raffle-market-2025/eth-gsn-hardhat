// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./LibraryStruct.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol"; // we inherit from the interfaces just to make sure that we implement those functions
import "./IRaffleMarketplace.sol";
import "./RaffleNFT.sol";

/*
    TODO:
    register the contract with chainlink keepers
    send prizes to the winners - need to discuss this
    send the money collected to the hoster - need to discuss this
    if the threshold is not passed, revert the lottery and send the tickets money back to the players
   

 */

error Raffle__NotEnougEthEntered();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint256 state, uint256 balance, uint256 playersLength);
error Raffle__OnlyHosterAllowed();
error Raffle__NotEnoughTicketsAvailable();
error Raffle__OnlyMarketplaceOwnerAllowed();
error Raffle__RaffleNotOpen(RaffleLibrary.RaffleState raffleState);
error Raffle__RaffleNotFinished();

contract RaffleContract is VRFConsumerBaseV2, KeeperCompatibleInterface {
    // interface of marketplace contract to update the winners
    IRaffleMarketplace raffleMarketplace;

    // mapping with stageType to stages in a raffle
    mapping(uint256 => RaffleLibrary.RaffleStage) raffleStages;
    // array of raffle stages
    RaffleLibrary.RaffleStage[] raffleStagesArray;

    // players struct to track which player bought which ticket at what price, needed to send the money back if the lottery is reverted

    // raffle id in the marketplace contract
    uint256 raffleId;
    // how long should the raffle go on
    uint256 durationOfRaffle;
    // minimum amount of money collected from selling the tickets to say that the raffle is successfull
    uint256 threshold;
    // hoster of raffle
    address payable raffleOwner;
    // no of winners to pick, equal to the number of prizes available
    uint32 noOfWinnersToPick;
    // array of players entered in the raffle
    address payable[] private s_players;
    // tokens ids in Raffle
    RaffleLibrary.Players[] private tokensInRaffle;
    // state of raffle - OPEN,CALCULATIN
    RaffleLibrary.RaffleState private s_raffleState;
    // current stage in which the raffle is in - SALE,PRESALE etc. converted to uint
    uint256 private currentStage;

    address marketplaceOwner;
    //address of NFT smart contract
    address RaffleNFt;
    //address of marketplace
    address marketplace;

    // Chainlink variables

    // vrfCoordinatorV2 contract which we use to reques the random number
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    // minimum gas we are willing to pay
    bytes32 private immutable i_gasLane;
    // our contract subscription id
    uint64 private immutable i_subscriptionId;
    // how much confirmations should the chainlink node wait before sending the response
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    // how much gas should chainlink node use while calling fulfillRandomWords of our contract
    uint32 private immutable i_callbackGasLimit;
    // array of winners picked after the raffle is completed
    address[] private s_recentWinners;

    RaffleLibrary.RafflePrize[] private prizes;

    //events
    event RaffleEntered(address indexed player);
    // event emitted when we request a random number
    event RequestedRaffleWinner(uint256 indexed reqId);
    // event emitted when a player enters a raffle
    event WinnersPicked(address payable[] indexed winners);

    constructor(
        uint256 _raffleId,
        uint256 _durationOfRaffle,
        uint256 _threshold,
        address payable _raffleOwner,
        address _marketplceOwner,
        RaffleLibrary.RafflePrize[] memory _prizes,
        RaffleLibrary.RaffleStage[] memory _stages,
        address vrfCoordinatorV2,
        address _marketplace,
        uint64 subscriptionId
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        raffleId = _raffleId;
        durationOfRaffle = block.timestamp + _durationOfRaffle;
        threshold = _threshold;
        raffleOwner = _raffleOwner;
        _addPrizeInStorage(_prizes);
        _addStageInStorage(_stages);
        noOfWinnersToPick = uint32(prizes.length);
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = 2500000;
        raffleMarketplace = IRaffleMarketplace(_marketplace);
        // once a raffle contract is deployed, the state is OPEN
        s_raffleState = RaffleLibrary.RaffleState.OPEN;
        marketplaceOwner = _marketplceOwner;     
        marketplace = _marketplace;   
    }

    function createNftContract(string memory _baseURI, string memory _name, string memory _symbol) external onlyMarketplace {
            uint _max_supply = totalTickets();
            RaffleNFTs raffleNfts = new RaffleNFTs(
                    _baseURI,
                    address(this),
                    _name,
                    _symbol,
                    _max_supply
            );
            RaffleNFt = address(raffleNfts);

    }

    // Enter the raffle
    //TODO: fix error here
    function enterRaffle() external payable isRaffleOpen {
        // we check if the total tickets of current stage are sold
        /* For example, there are 100 tickets in PRESALE stage and all 100 are sold, then we automatically move to SALE stage whose ticket price is higher*/
        updateCurrentStage();
        RaffleLibrary.RaffleStage storage curStage = raffleStages[currentStage];
        // if money sent is less than the ticket price, revert
        if (msg.value < curStage.ticketPrice) {
            revert Raffle__NotEnougEthEntered();
        }
        // calculate how much tickets did the user bought
        // for example, if the ticket price is 10 MATIC and the user sent 100 MATIC, then the tickets bought = 10
        // more the tickets bought, more is the chance of winning the raffle
        uint256 ticketsBought = msg.value / curStage.ticketPrice;

        if (ticketsBought > (curStage.ticketsAvailable - curStage.ticketsSold)) {
            revert Raffle__NotEnoughTicketsAvailable();
        }
        curStage.ticketsSold += ticketsBought;

        for (uint256 i = 0; i < ticketsBought; i++) {
            (bool transferred, uint mintedTokenId) = RaffleNFTs(RaffleNFt).mintNFTs(msg.sender);
            require(transferred, "Can't transfer");
            tokensInRaffle.push(RaffleLibrary.Players(curStage.ticketPrice, mintedTokenId));
            //s_players.push(RaffleLibrary.Players(curStage.ticketPrice, msg.sender));
        }
        for (uint256 i = 0; i < raffleStagesArray.length; i++) {
            if (raffleStagesArray[i].stageType == curStage.stageType) {
                raffleStagesArray[i].ticketsSold += ticketsBought;
            }
        }
        // TODO: uncomment this after tests
        raffleMarketplace.updateTicketsSold(raffleId, curStage.stageType, ticketsBought,msg.sender);
        updateCurrentStage(); //TODO: Not working, need to fix this, critical 
        emit RaffleEntered(msg.sender);
    }

    //TODO: fix this major bug!!!!
    // //internal function used to update the current stage to  next stage
    function updateCurrentStage() internal {
        uint256 nextStageType;
        if (raffleStages[currentStage].ticketsSold == raffleStages[currentStage].ticketsAvailable) {

            for (uint256 i = 0; i < raffleStagesArray.length; i++) {
             
                if (
                    uint256(raffleStagesArray[i].stageType) > currentStage &&
                    raffleStagesArray[i].ticketsAvailable != 0
                ) { 
                  
                    nextStageType = uint256(raffleStagesArray[i].stageType);
                    currentStage = nextStageType;
                    
                    raffleMarketplace.updateCurrentOngoingStage(
                        raffleId,
                        RaffleLibrary.StageType(currentStage)
                    );
                    return;
                }
            }
        }
    }

    /* This func is called by chainlink keeper node to check if we can perform upkeep or not
    If the result is true, then we pick a random number:
    1. The time interval of raffle should end
    2. The threshold should pass
    3. Our subscription is funded with link
    4. The lottery should be in OPEN state
    */

    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /*performData */
        )
    {
        bool isOpen = (s_raffleState == RaffleLibrary.RaffleState.OPEN);
        bool isTimeFinished = (block.timestamp > durationOfRaffle);
        bool hasThreshold = isThresholdPassed();
        bool hasPlayers = (tokensInRaffle.length > 0);
        upkeepNeeded = (isOpen && isTimeFinished && hasPlayers && hasThreshold);
    }

    // to pick a random winner
    // get a random numbber and do something with it
    // chainlink vrf is a 2 tx process, its intentional as having it in 2 txs is better than having in 1tx, to prevent the manipulation

    // This function just requests for a random number, some other func will return the random no
    function performUpkeep(
        bytes memory /*performUpkeep */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");

        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                uint256(s_raffleState),
                address(this).balance,
                tokensInRaffle.length
            );
        }

        s_raffleState = RaffleLibrary.RaffleState.CALCULATING;
        // TODO: uncomment below after test
        raffleMarketplace.updateRaffleState(raffleId,s_raffleState);

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane or key hash - the maximum number of gas in wei you are willing to spend for random number,
            i_subscriptionId, // the id of the subscription of chainlink vrf,
            REQUEST_CONFIRMATIONS, // requestConfirmations - How many confirmations the chhainlink node should wait before sending the response
            i_callbackGasLimit, // callbackGasLimit - how many gas should the chainlink node use to call fulfill random words of our contract
            noOfWinnersToPick // noOfWinnersToPick - how many random numbers  to pick
        );
        emit RequestedRaffleWinner(requestId);
    }

    // returns the random number, this func is called by chainlink vrf
    function fulfillRandomWords(
        uint256, /*requestId*/
        uint256[] memory randomWords
    ) internal override {
        //address[] memory temp = RaffleLibrary._shuffle(s_players);
        for(uint i = 0; i < tokensInRaffle.length; i++) {            
            s_players.push(payable(RaffleNFTs(RaffleNFt).ownerOf(tokensInRaffle[i].id)));
        }
        address payable[] memory winners = new address payable[](noOfWinnersToPick);
        for (uint256 i = 0; i < randomWords.length; i++) {
            uint256 randomIndex = randomWords[i] % tokensInRaffle.length;
            winners[i] = s_players[randomIndex];
        }
        s_recentWinners = winners;
        // update the winners in the marketplace contract
        raffleMarketplace.updateWinners(raffleId, winners);
        s_raffleState = RaffleLibrary.RaffleState.FINISHED;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);

        emit WinnersPicked(winners);

        for (uint i = 0; i < s_players.length; i++) {
           RaffleNFTs(RaffleNFt).burn(s_players[i]);  
        }        
    }

    // function to revert the lottery if its not successfull
    function revertLottery() external onlyHoster onlyMarketplaceOwner {
        require(s_raffleState == RaffleLibrary.RaffleState.OPEN);
        for (uint256 i = 0; i < tokensInRaffle.length; i++) {
            payable(RaffleNFTs(RaffleNFt).ownerOf(tokensInRaffle[i].id)).transfer(tokensInRaffle[i].ticketPrice);
        }
        s_raffleState = RaffleLibrary.RaffleState.REVERTED;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);
    }

    function distributePrizes() public onlyMarketplaceOwner {
        if (s_raffleState != RaffleLibrary.RaffleState.FINISHED) {
            revert Raffle__RaffleNotFinished();
        }
        uint256 count = 0;
        for (uint256 i = 0; i < prizes.length; i++) {
            if (prizes[i].prizeAmount != 0 && count < s_recentWinners.length) {
                (bool sent, ) = payable(s_recentWinners[count]).call{value: prizes[i].prizeAmount}(
                    ""
                );
                count++;
                require(sent);
            }
        }
    }

    function _addStageInStorage(RaffleLibrary.RaffleStage[] memory _stages) internal {
        for (uint256 i = 0; i < _stages.length; i++) {
            raffleStages[uint256(_stages[i].stageType)] = (
                RaffleLibrary.RaffleStage(
                    _stages[i].stageType,
                    _stages[i].ticketsAvailable,
                    _stages[i].ticketPrice,
                    0
                )
            );

            raffleStagesArray.push(
                RaffleLibrary.RaffleStage(
                    _stages[i].stageType,
                    _stages[i].ticketsAvailable,
                    _stages[i].ticketPrice,
                    0
                )
            );
        }

        currentStage = uint256(_stages[0].stageType);
    }

    function _addPrizeInStorage(RaffleLibrary.RafflePrize[] memory _prizes) internal {
        for (uint256 i = 0; i < _prizes.length; i++) {
            prizes.push(
                RaffleLibrary.RafflePrize(

                    _prizes[i].prizeTitle,
                    _prizes[i].country,
                    _prizes[i].prizeAmount
                )
            );
        }
    }

    function _sendFundsToMarketplace() external onlyMarketplaceOwner {
        (bool sent, ) = address(raffleMarketplace).call{value: address(this).balance}("");
        require(sent);
    }

    function getRaffleId() public view returns (uint256) {
        return raffleId;
    }

    function getEntraceFee() external view returns (uint256) {
        return raffleStages[currentStage].ticketPrice;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return tokensInRaffle.length;
    }

    function getRecentWinners() external view returns (address[] memory) {
        return s_recentWinners;
    }

    function getCurrentStage() external view returns (RaffleLibrary.RaffleStage memory) {
        return raffleStages[currentStage];
    }

    function getStages() external view returns (RaffleLibrary.RaffleStage[] memory) {
        return raffleStagesArray;
    }

    function getStageInformation(uint256 stageType)
        external
        view
        returns (RaffleLibrary.RaffleStage memory)
    {
        return raffleStages[stageType];
    }

    function getCurrentState() external view returns (RaffleLibrary.RaffleState) {
        return s_raffleState;
    }

    function totalTicketsSold() public view returns (uint256) {
        uint256 count = 0;
        for (uint32 i = 0; i < raffleStagesArray.length; i++) {
            count += raffleStagesArray[i].ticketsSold;
        }
        return count;
    }

    function totalTickets() public view returns (uint256) {
        uint256 count = 0;
        for (uint32 i = 0; i < raffleStagesArray.length; i++) {
            count += raffleStagesArray[i].ticketsAvailable;
        }
        return count;
    }

    function ticketsSoldByStage(uint256 stageType) external view returns (uint256) {
        return raffleStages[stageType].ticketsSold;
    }

    function getCurrentThresholdValue() public view returns (uint256) {
        return (totalTicketsSold() * 100) / totalTickets();
    }

    function isThresholdPassed() public view returns (bool) {
        bool isThreshold = (getCurrentThresholdValue() >= threshold);
        return isThreshold;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function NftAddress() public view returns (address) {
        return RaffleNFt;
    }

    modifier isRaffleOpen() {
        if (s_raffleState != RaffleLibrary.RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        _;
    }

    modifier onlyHoster() {
        _onlyHoster();
        _;
    }

    function _onlyHoster() internal view {
        if (msg.sender != raffleOwner) {
            revert Raffle__OnlyHosterAllowed();
        }
    }

    modifier onlyMarketplaceOwner() {
        _onlyMarketplaceOwner();
        _;
    }

    function _onlyMarketplaceOwner() internal view {
        if (msg.sender != marketplaceOwner) {
            revert Raffle__OnlyMarketplaceOwnerAllowed();
        }
    }

    modifier onlyMarketplace() {
        require(msg.sender == marketplace, "No access");
        _;
    }
}
