// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// The raffle contract where people will directly interact to enter / win a raffle
import "./Raffle.sol";
// A Library to contain RaffleStage struct in both the contracts
import "./LibraryStruct.sol";
import "./IVerifier.sol";

import "./RegisterUpkeep.sol";
import "./VRFSubscribe.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// It means throw an error when the raffle does not exist
error RaffleMarketplace__InvalidTickerId();
// It means throw an error when the raffle has not been deployed as in created yet
error RaffleMarketplace__RaffleNotCreated(uint256 id);
// It means only the hoster of raffle can access specific functions
error RaffleMarketplace__OnlyHosterAllowed(address caller, address hoster);
error RaffleMarketplace__OnlyOwnerAllowed();
error RaffleMarketplace__PrizeDoesNotExist(uint256 raffleId, uint256 prizeId);
error RaffleMarketplace__PrizeAlreadyExist(uint256 raffleId, uint256 prizeId);
error RaffleMarketplace__StageAlreadyExist(uint256 raffleId, RaffleLibrary.StageType stageType);
// error RaffleMarketplace__StageDoesNotExist(uint256 raffleId,Stage.StageType stageType);

error RaffleMarketplace__StageDoesNotExist(uint256 raffleId, RaffleLibrary.StageType stageType);
error RaffleMarketplace__RaffleNotVerified();
error RaffleMarketplace__RaffleVerified();

// error RaffleMarketplace__PrizeDoesNotExist(uint256 raffleId, uint256 prizeId);

contract RaffleMarketplace is  VRFV2SubscriptionManager,RaffleRegisterUpkeep {
    /*
        1. Create raffle
        2. Cancel raffle (to be done before the winner is picked, and send the money back to the people)

        */


    event RaffleCreated(
        uint256 indexed raffleTicker,
        address  hoster,
        RaffleLibrary.Raffle  raffle,
        RaffleLibrary.RaffleStage[] stages,
        RaffleLibrary.RafflePrize[] prizes,
        RaffleLibrary.StageType ongoingStage
    );
    event RaffleVerified(uint256 indexed raffleTicker, address indexed deployedRaffle);
    event RaffleStageAdded(uint256 indexed raffleTicker, RaffleLibrary.RaffleStage  stage);
    event RaffleWinnersPicked(uint256 indexed raffleTicker, address payable[]  winners);
    event RaffleStateUpdated(uint256 indexed raffleTicker, RaffleLibrary.RaffleState indexed state);
    event RaffleStageTicketPriceUpdated(
        uint256 indexed raffleTicker,
        RaffleLibrary.StageType indexed stageType,
        uint256 indexed price
    );
    event RaffleStageTicketAvailabilityUpdated(
        uint256 indexed raffleTicker,
        RaffleLibrary.StageType indexed stageType,
        uint256 indexed availability
    );
    event RaffleTicketBought(
        uint256 indexed raffleTicker,
        RaffleLibrary.StageType indexed stageType,
        uint256 indexed ticketsBought,
        address  rafflePlayer
    );
    event RaffleStageUpdated(uint256 indexed raffleTicker,RaffleLibrary.StageType indexed currentStage);

    // To keep track of the raffles
    uint256 raffleTicker;
    
    //Raffle verifier address
    address raffleVerifier;

    // Different raffle categories, entered by frontend
    
    // Chainlink VRF

   
    

    //Chainlink Keepers

   

    constructor(address vrfCoordinator,address linkTokenAddress,address registrar, address _raffleVerifier) VRFV2SubscriptionManager(vrfCoordinator, linkTokenAddress) RaffleRegisterUpkeep(linkTokenAddress,registrar) {
        // initializes raffleTicker to 1
        raffleTicker = 1;
        owner = msg.sender;
        raffleVerifier = _raffleVerifier;
    }

    // mapping of raffle identifer to raffles created
    mapping(uint256 => RaffleLibrary.Raffle) _raffles;
    // mapping of raffle identifer to raffles hosters
    mapping(uint256 => address) _raffleHosterAddress;
    // mapping of raffle identifer to raffle prizes
    mapping(uint256 => RaffleLibrary.RafflePrize[]) _raffleToRafflePrizes;
    // mapping of raffle identifer to raffle stages
    mapping(uint256 => RaffleLibrary.RaffleStage[]) _raffleToRaffleStages;
    // mapping of raffle identifer to ongoing stages
    mapping(uint256 => RaffleLibrary.StageType) _raffleToOngoingStages;

    // creates a raffle
    // TODO: emit createdRaffle event
    function createRaffle(
        RaffleLibrary.RaffleCategory _category,
        string memory title,
        string memory description,
        uint256 raffleDuration,
        uint256 threshold,
        string[] memory images,
        RaffleLibrary.RafflePrize[] memory prizes,
        RaffleLibrary.CharityInformation memory charityInfo,
        RaffleLibrary.RaffleStage[] memory stages
        
    ) external {
        // adds raffle to the mapping
        address payable[] memory winners = new address payable[](prizes.length);
        RaffleLibrary.Raffle memory raffleStruct = RaffleLibrary.Raffle(
            raffleTicker,
            false,
            address(0),
            _category,
            title,
            description,
            raffleDuration,
            threshold,
            images,
            charityInfo,
            winners,
        
            RaffleLibrary.RaffleState.NOT_INITIALIZED
        );
        
        _raffles[raffleTicker] = raffleStruct;

        // adds stages to the mapping by raffle id
        _addStageInStorage(stages);
        // adds prizes to the mapping by raffle id
        
        _addPrizeInStorage(prizes);
        // adds hoster of the raffle to mapping by raffle id
        _raffleHosterAddress[raffleTicker] = msg.sender;


        //TODO: fix this, the stage doesnt work if the stage is not 0 initially
        _raffleToOngoingStages[raffleTicker] = stages[0].stageType;

        emit RaffleCreated(
            raffleTicker,
            msg.sender,
            _raffles[raffleTicker],
            _raffleToRaffleStages[raffleTicker],
            _raffleToRafflePrizes[raffleTicker],
            _raffleToOngoingStages[raffleTicker]
        );
        // increments raffle id for next raffle
        raffleTicker++;
    }

    // A User only enters the raffle details, once the owner of marketplace verifies that it is genuine, then the raffle starts and is open for entries
    /*
     TODO:
     update the depployed with correct args
     */

    // once a raffle is created, marketplace owner verifies it and starts the raffle by deploying the raffle contract
    function verifyRaffle(uint256 _id) external invalidTickerId(_id) doesRaffleExists(_id) onlyOwner {
        uint32 gasLimit = 5000000;
        uint96 amount = 5 ether;
        bytes memory data = new bytes(0);
        // get the raffle of that id
        RaffleLibrary.Raffle storage raffleStruct = _raffles[_id];
        // verify the raffle
        _raffles[_id].isVerifiedByMarketplace = true;
        raffleStruct.raffleState = RaffleLibrary.RaffleState.OPEN;
        

        // deploy the raffle contract
        IVerifier.toPassFunc memory toFunc = IVerifier.toPassFunc(
            _id,
            raffleStruct.raffleDuration,
            raffleStruct.threshold,
            payable(_raffleHosterAddress[_id]),
            owner,
            _raffleToRafflePrizes[_id],
            _raffleToRaffleStages[_id],
            address(COORDINATOR),
            s_subscriptionId
        );
        address raffle = IVerifier(raffleVerifier).deployRaffle(
            toFunc
        );
        
        _raffles[_id].raffleAddress = raffle;

        /*
        RaffleContract raffle = new RaffleContract(
            _id,
            raffleStruct.raffleDuration,
            raffleStruct.threshold,
            payable(_raffleHosterAddress[_id]),
            owner,
            _raffleToRafflePrizes[_id],
            _raffleToRaffleStages[_id],
            address(COORDINATOR),
            s_subscriptionId
        );

        //update the deployed address in the raffle struct

        _raffles[_id].raffleAddress = address(raffle);
*/
        //create NFT Raffle smart contract and deploy it
        //raffle.createNftContract(_baseURI, address(raffle), "Raffle", "Raffle#1", _price, _max_supply);
        //_raffles[_id].raffleState = RaffleLibrary.RaffleState.OPEN;
        emit RaffleStateUpdated(_id, _raffles[_id].raffleState);
      
        addConsumer(_raffles[_id].raffleAddress);        
        registerAndPredictID(_raffles[_id].title,data,_raffles[_id].raffleAddress,gasLimit,owner,data,amount,110);

        //create NFT contract         
        RaffleContract(raffle).createNftContract(raffleStruct.images[0], "RAFFLE", "RAFFLE");
        // emit a raffle verified event
        emit RaffleVerified(_id, raffle);
    }

    // function to add new stages to a raffle - can only be called before the marketplace owner verifies and starts the raffle
    /*
    TODO: add modifier to check if the raffle is not verified before allowing to add a stage
    
    */
    function addStage(
        uint256 raffleId,
        RaffleLibrary.StageType stageType,
        uint256 ticketsAvailable,
        uint256 ticketPrice
    )
        external
        invalidTickerId(raffleId)
        onlyRaffleHoster(raffleId)
        isRaffleNotVerified(raffleId)
        raffleStageNotExists(raffleId, stageType)
    {
        // gets the next stage id

        RaffleLibrary.RaffleStage memory stage = RaffleLibrary.RaffleStage(
            stageType,
            ticketsAvailable,
            ticketPrice,
            0
        );
        _raffleToRaffleStages[raffleId].push(stage);
        emit RaffleStageAdded(raffleId, stage);
    }


    // function to modify the ticket price of a particular stage - can only be called before the owner verifies the raffle
    // TODO: add modifier to check if the raffle is only in created state not openeed
    function modifyStagePrice(
        uint256 raffleId,
        RaffleLibrary.StageType stageType,
        uint256 ticketAmount
    )
        external
        invalidTickerId(raffleId)
        onlyRaffleHoster(raffleId)
        isRaffleNotVerified(raffleId)
        doesRaffleExists(raffleId)
        raffleStageExists(raffleId, stageType)
    {
        RaffleLibrary.RaffleStage[] storage stages = _raffleToRaffleStages[raffleId];
        for (uint256 i = 0; i < stages.length; i++) {
            if (stages[i].stageType == stageType) {
                stages[i].ticketPrice = ticketAmount;
            }
        }
        emit RaffleStageTicketPriceUpdated(raffleId, stageType, ticketAmount);
    }

    // function to modify the number of tickets available in the stage- can only be called before the owner verifies the raffle
    function modifyStageTickets(
        uint256 raffleId,
        RaffleLibrary.StageType stageType,
        uint256 ticketsAvailable
    )
        external
        invalidTickerId(raffleId)
        onlyRaffleHoster(raffleId)
        doesRaffleExists(raffleId)
        isRaffleNotVerified(raffleId)
        raffleStageExists(raffleId, stageType)
    {
        RaffleLibrary.RaffleStage[] storage stages = _raffleToRaffleStages[raffleId];
        for (uint256 i = 0; i < stages.length; i++) {
            if (stages[i].stageType == stageType) {
                stages[i].ticketsAvailable = ticketsAvailable;
            }
        }
        emit RaffleStageTicketAvailabilityUpdated(raffleId, stageType, ticketsAvailable);
    }

   

   
    

    // internal function to add stage passed in memory as storage
    function _addStageInStorage(RaffleLibrary.RaffleStage[] memory _stages) internal {
        for (uint256 i = 0; i < _stages.length; i++) {
            _raffleToRaffleStages[raffleTicker].push(
                RaffleLibrary.RaffleStage(
                    _stages[i].stageType,
                    _stages[i].ticketsAvailable,
                    _stages[i].ticketPrice,
                    0
                )
            );
        }
    }

    // internal function to add prize passed in memory as storage
    function _addPrizeInStorage(RaffleLibrary.RafflePrize[] memory _prizes) internal {
        for (uint256 i = 0; i < _prizes.length; i++) {
            _raffleToRafflePrizes[raffleTicker].push(
                RaffleLibrary.RafflePrize(_prizes[i].prizeTitle, _prizes[i].country, _prizes[i].prizeAmount)
            );
        }
    }

   

    // function to be called by the raffle contract to update the winners of a raffle
    function updateWinners(uint256 id, address payable[] memory winners)
        external
        onlyRaffleContract(id)
    {
        _raffles[id].winners = winners;
        emit RaffleWinnersPicked(id, winners);
    }

    function updateRaffleState(uint256 id, RaffleLibrary.RaffleState state)
        external
        onlyRaffleContract(id)
    {
        _raffles[id].raffleState = state;
        emit RaffleStateUpdated(id, state);
    }

    function updateTicketsSold(
        uint256 id,
        RaffleLibrary.StageType stageType,
        uint256 ticketsBought, address rafflePlayer

    ) external onlyRaffleContract(id) {
        for (uint256 i = 0; i < _raffleToRaffleStages[id].length; i++) {
            if (_raffleToRaffleStages[id][i].stageType == stageType) {
                _raffleToRaffleStages[id][i].ticketsSold = _raffleToRaffleStages[id][i].ticketsSold + ticketsBought;
                emit RaffleTicketBought(
                    id,
                    _raffleToRaffleStages[id][i].stageType,
                 ticketsBought,
                    rafflePlayer
                );
            }
        }
    }

    function updateCurrentOngoingStage(uint256 id, RaffleLibrary.StageType stageType)
        external
        onlyRaffleContract(id)
    {
        _raffleToOngoingStages[id] = stageType;
        emit RaffleStageUpdated(id,stageType);
    }

    // returns next ticker of the raffle to be created
    function getNextTickerId() external view returns (uint256) {
        return raffleTicker;
    }

    // returns all the information of the raffle using raffle id / ticker
    function getRaffleById(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (
            RaffleLibrary.Raffle memory,
            RaffleLibrary.RafflePrize[] memory,
            RaffleLibrary.RaffleStage[] memory
        )
    {
        return (_raffles[id], _raffleToRafflePrizes[id], _raffleToRaffleStages[id]);
    }

    // returns the address of hoster and the raffle info using id

    // returns only the hoster of a raffle by id
    function getRaffleHosterById(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (address)
    {
        return _raffleHosterAddress[id];
    }

    
  

    // returns stage information of the raffle
    function getRaffleStagesById(uint256 id)
        public
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (RaffleLibrary.RaffleStage[] memory)
    {
        return _raffleToRaffleStages[id];
    }

    function getParticularRaffleStage(uint256 id, RaffleLibrary.StageType stageType)
        external
        view
        invalidTickerId(id)
        raffleStageExists(id, stageType)
        returns (RaffleLibrary.RaffleStage memory)
    {
        RaffleLibrary.RaffleStage[] memory stage = getRaffleStagesById(id);
        for (uint256 i = 0; i < stage.length; i++) {
            if (stage[i].stageType == stageType) {
                return stage[i];
            }
        }
    }

    function getOngoingRaffleStage(uint256 id) public view returns (RaffleLibrary.StageType) {
        return _raffleToOngoingStages[id];
    }

    // returns address of the deployed raffle contract
    function getRaffleAddress(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (address)
    {
        return _raffles[id].raffleAddress;
    }

    function getRaffleVerificationInfo(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (bool)
    {
        return _raffles[id].isVerifiedByMarketplace;
    }

    // checks if the raffle is deployed
    function _doesRaffleExists (uint256 id) view private  {
        if (_raffles[id].id == 0) {
            revert RaffleMarketplace__RaffleNotCreated(id);
        }
        
    }

     modifier doesRaffleExists(uint256 id){
         _doesRaffleExists(id);
         _;
     }

    // checks that the entered id is not <=0
    function _invalidTickerId(uint256 _id) pure internal {
        if (_id <= 0) {
            revert RaffleMarketplace__InvalidTickerId();
        }
        
    }

    modifier  invalidTickerId(uint256 _id){
        _invalidTickerId(_id);
        _;
    }

    // checks that only the raffle hoster can call the function
    function _onlyRaffleHoster(uint256 _id) internal view {
        if (msg.sender != _raffleHosterAddress[_id]) {
            revert RaffleMarketplace__OnlyHosterAllowed(msg.sender, _raffleHosterAddress[_id]);
        }
        
    }

    modifier onlyRaffleHoster(uint256 _id){
        _onlyRaffleHoster(_id);
        _;
    }

    // checks if a particular stage exists
    function _raffleStageExists(uint256 raffleId, RaffleLibrary.StageType stageType) view internal {
        if (!doesRaffleStageExists(raffleId, stageType)) {
            revert RaffleMarketplace__StageDoesNotExist(raffleId, stageType);
        }
        
    }

    modifier raffleStageExists(uint256 raffleId, RaffleLibrary.StageType stageType){
        _raffleStageExists(raffleId,stageType);
        _;
    }

    // checks if a particular stage does not exists
    function _raffleStageNotExists(uint256 raffleId,RaffleLibrary.StageType stageType) view  internal {
        if (doesRaffleStageExists(raffleId, stageType)) {
            revert RaffleMarketplace__StageAlreadyExist(raffleId, stageType);
        }

    
    }

    modifier  raffleStageNotExists(uint256 raffleId,RaffleLibrary.StageType stageType){
        _raffleStageNotExists(raffleId, stageType);
        _;
    }



    function _onlyRaffleContract(uint256 id)  view internal {
        require(
            (msg.sender == _raffles[id].raffleAddress) && (_raffles[id].raffleAddress != address(0))
        );
        
    }

    modifier onlyRaffleContract(uint256 id){
        _onlyRaffleContract(id);
        _;
    }

    // same function to see if stage exists or not
    function doesRaffleStageExists(uint256 raffleId, RaffleLibrary.StageType stageType)
        public
        view
        returns (bool)
    {
        RaffleLibrary.RaffleStage[] memory stage = getRaffleStagesById(raffleId);

        bool stageExists;
        for (uint256 i = 0; i < stage.length; i++) {
            if (stage[i].stageType == stageType) {
                stageExists = true;
            }
        }
        return stageExists;
    }

   
    
    // to check if the raffle is verified
    function _isRaffleVerified(uint256 id) view private {
        if (!_raffles[id].isVerifiedByMarketplace) {
            revert RaffleMarketplace__RaffleNotVerified();
        }
        
    }

    modifier isRaffleVerified(uint256 id){
        _isRaffleVerified(id);
        _;
    }

    //to check if the raffle is not verified
    function _isRaffleNotVerified(uint256 id) view private {
        if (_raffles[id].isVerifiedByMarketplace) {
            revert RaffleMarketplace__RaffleVerified();
        }
        
    }

    modifier isRaffleNotVerified(uint256 id) {
        _isRaffleNotVerified(id);
        _;
    }

    function updateOwner(address _owner) external onlyOwner{
        owner=_owner;
    }

   
}
