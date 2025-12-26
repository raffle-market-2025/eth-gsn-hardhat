// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Core structs/enums shared across contracts
import "./LibraryStruct.sol";

// Deploys raffle contract (direct deploy in this version)
import "./Raffle.sol";

/* =========================
   Errors
========================= */

error RaffleMarketplace__InvalidTickerId();
error RaffleMarketplace__RaffleNotCreated(uint256 id);
error RaffleMarketplace__OnlyHosterAllowed(address caller, address hoster);
error RaffleMarketplace__OnlyOwnerAllowed();

error RaffleMarketplace__PrizeDoesNotExist(uint256 raffleId, uint256 prizeId);
error RaffleMarketplace__PrizeAlreadyExist(uint256 raffleId, uint256 prizeId);

error RaffleMarketplace__StageAlreadyExist(uint256 raffleId, RaffleLibrary.StageType stageType);
error RaffleMarketplace__StageDoesNotExist(uint256 raffleId, RaffleLibrary.StageType stageType);

error RaffleMarketplace__RaffleNotVerified();
error RaffleMarketplace__RaffleVerified();

/* =========================
   Contract
========================= */

contract RaffleMarketplace {
    /* =========================
       Events
    ========================= */

    event RaffleCreated(
        uint256 indexed raffleTicker,
        address hoster,
        RaffleLibrary.Raffle raffle,
        RaffleLibrary.RaffleStage[] stages,
        RaffleLibrary.RafflePrize[] prizes,
        RaffleLibrary.StageType ongoingStage
    );

    event RaffleVerified(uint256 indexed raffleTicker, address indexed deployedRaffle);

    event RaffleStageAdded(uint256 indexed raffleTicker, RaffleLibrary.RaffleStage stage);

    event RaffleWinnersPicked(uint256 indexed raffleTicker, address payable[] winners);

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
        address rafflePlayer
    );

    event RaffleStageUpdated(uint256 indexed raffleTicker, RaffleLibrary.StageType indexed currentStage);

    /* =========================
       Storage
    ========================= */

    // Next raffle id to be created
    uint256 private raffleTicker;

    // Admin (marketplace owner)
    address public owner;

    // mapping of raffleId -> raffle struct
    mapping(uint256 => RaffleLibrary.Raffle) private _raffles;

    // raffleId -> hoster address
    mapping(uint256 => address) private _raffleHosterAddress;

    // raffleId -> prizes
    mapping(uint256 => RaffleLibrary.RafflePrize[]) private _raffleToRafflePrizes;

    // raffleId -> stages
    mapping(uint256 => RaffleLibrary.RaffleStage[]) private _raffleToRaffleStages;

    // raffleId -> ongoing stage (mirrored view; updated by raffle contract)
    mapping(uint256 => RaffleLibrary.StageType) private _raffleToOngoingStages;

    /* =========================
       Constructor
    ========================= */

    constructor() {
        owner = msg.sender;
        raffleTicker = 1;
    }

    /* =========================
       Create / Verify
    ========================= */

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
        // winners placeholder (length = prizes.length)
        address payable[] memory winners = new address payable[](prizes.length);

        RaffleLibrary.Raffle memory raffleStruct = RaffleLibrary.Raffle(
            raffleTicker,
            false,              // isVerifiedByMarketplace
            address(0),         // raffleAddress (deployed later)
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

        _raffleHosterAddress[raffleTicker] = msg.sender;

        _addStageInStorage(raffleTicker, stages);
        _addPrizeInStorage(raffleTicker, prizes);

        // initial ongoing stage = stages[0]
        require(stages.length > 0, "RaffleMarketplace: no stages");
        _raffleToOngoingStages[raffleTicker] = stages[0].stageType;

        emit RaffleCreated(
            raffleTicker,
            msg.sender,
            _raffles[raffleTicker],
            _raffleToRaffleStages[raffleTicker],
            _raffleToRafflePrizes[raffleTicker],
            _raffleToOngoingStages[raffleTicker]
        );

        raffleTicker++;
    }

    /**
     * @notice Marketplace owner verifies raffle and deploys its RaffleContract.
     * @dev IMPORTANT: because RaffleContract.setAutomation() is onlyMarketplaceOwner (EOA),
     *      you must call setAutomation() from the owner EOA directly (e.g. in deploy script),
     *      not from inside this contract.
     */
    function verifyRaffle(uint256 id)
        external
        invalidTickerId(id)
        doesRaffleExists(id)
        onlyOwner
        isRaffleNotVerified(id)
    {
        RaffleLibrary.Raffle storage raffleStruct = _raffles[id];

        // mark verified and open
        raffleStruct.isVerifiedByMarketplace = true;
        raffleStruct.raffleState = RaffleLibrary.RaffleState.OPEN;

        // deploy raffle contract (no VRF inside raffle anymore)
        RaffleContract raffle = new RaffleContract(
            id,
            raffleStruct.raffleDuration,
            raffleStruct.threshold,
            payable(_raffleHosterAddress[id]),
            owner, // marketplaceOwner on raffle = this owner EOA
            _raffleToRafflePrizes[id],
            _raffleToRaffleStages[id],
            address(this) // marketplace contract address
        );

        raffleStruct.raffleAddress = address(raffle);

        emit RaffleStateUpdated(id, raffleStruct.raffleState);

        // deploy NFT contract for tickets (baseURI from first image by your convention)
        // name/symbol can be customized later if you want
        string memory baseURI = "";
        if (raffleStruct.images.length > 0) {
            baseURI = raffleStruct.images[0];
        }
        raffle.createNftContract(baseURI, "RAFFLE", "RAFFLE");

        emit RaffleVerified(id, address(raffle));
    }

    /* =========================
       Stage management (pre-verify)
    ========================= */

    function addStage(
        uint256 raffleId,
        RaffleLibrary.StageType stageType,
        uint256 ticketsAvailable,
        uint256 ticketPrice
    )
        external
        invalidTickerId(raffleId)
        doesRaffleExists(raffleId)
        onlyRaffleHoster(raffleId)
        isRaffleNotVerified(raffleId)
        raffleStageNotExists(raffleId, stageType)
    {
        RaffleLibrary.RaffleStage memory stage = RaffleLibrary.RaffleStage(
            stageType,
            ticketsAvailable,
            ticketPrice,
            0
        );
        _raffleToRaffleStages[raffleId].push(stage);
        emit RaffleStageAdded(raffleId, stage);
    }

    function modifyStagePrice(
        uint256 raffleId,
        RaffleLibrary.StageType stageType,
        uint256 ticketAmount
    )
        external
        invalidTickerId(raffleId)
        doesRaffleExists(raffleId)
        onlyRaffleHoster(raffleId)
        isRaffleNotVerified(raffleId)
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

    function modifyStageTickets(
        uint256 raffleId,
        RaffleLibrary.StageType stageType,
        uint256 ticketsAvailable
    )
        external
        invalidTickerId(raffleId)
        doesRaffleExists(raffleId)
        onlyRaffleHoster(raffleId)
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

    /* =========================
       Callbacks from RaffleContract
       (only the deployed raffle contract can call these)
    ========================= */

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
        uint256 ticketsBought,
        address rafflePlayer
    ) external onlyRaffleContract(id) {
        for (uint256 i = 0; i < _raffleToRaffleStages[id].length; i++) {
            if (_raffleToRaffleStages[id][i].stageType == stageType) {
                _raffleToRaffleStages[id][i].ticketsSold =
                    _raffleToRaffleStages[id][i].ticketsSold + ticketsBought;

                emit RaffleTicketBought(id, stageType, ticketsBought, rafflePlayer);
                return;
            }
        }
        // if stage not found, we silently ignore (or revert if you want strictness)
    }

    function updateCurrentOngoingStage(uint256 id, RaffleLibrary.StageType stageType)
        external
        onlyRaffleContract(id)
    {
        _raffleToOngoingStages[id] = stageType;
        emit RaffleStageUpdated(id, stageType);
    }

    /* =========================
       Views required by Automation contract
    ========================= */

    function getNextTickerId() external view returns (uint256) {
        return raffleTicker;
    }

    function getRaffleAddress(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (address)
    {
        return _raffles[id].raffleAddress;
    }

    /* =========================
       Other views
    ========================= */

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

    function getRaffleHosterById(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (address)
    {
        return _raffleHosterAddress[id];
    }

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
        doesRaffleExists(id)
        raffleStageExists(id, stageType)
        returns (RaffleLibrary.RaffleStage memory)
    {
        RaffleLibrary.RaffleStage[] memory stages = _raffleToRaffleStages[id];
        for (uint256 i = 0; i < stages.length; i++) {
            if (stages[i].stageType == stageType) return stages[i];
        }
        // should be unreachable because of raffleStageExists
        revert RaffleMarketplace__StageDoesNotExist(id, stageType);
    }

    function getOngoingRaffleStage(uint256 id)
        external
        view
        invalidTickerId(id)
        doesRaffleExists(id)
        returns (RaffleLibrary.StageType)
    {
        return _raffleToOngoingStages[id];
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

    /* =========================
       Admin
    ========================= */

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    /* =========================
       Internal storage helpers
    ========================= */

    function _addStageInStorage(uint256 id, RaffleLibrary.RaffleStage[] memory stages) internal {
        require(stages.length > 0, "RaffleMarketplace: no stages");
        for (uint256 i = 0; i < stages.length; i++) {
            _raffleToRaffleStages[id].push(
                RaffleLibrary.RaffleStage(
                    stages[i].stageType,
                    stages[i].ticketsAvailable,
                    stages[i].ticketPrice,
                    0
                )
            );
        }
    }

    function _addPrizeInStorage(uint256 id, RaffleLibrary.RafflePrize[] memory prizes) internal {
        for (uint256 i = 0; i < prizes.length; i++) {
            _raffleToRafflePrizes[id].push(
                RaffleLibrary.RafflePrize(
                    prizes[i].prizeTitle,
                    prizes[i].country,
                    prizes[i].prizeAmount
                )
            );
        }
    }

    /* =========================
       Modifiers / checks
    ========================= */

    modifier onlyOwner() {
        if (msg.sender != owner) revert RaffleMarketplace__OnlyOwnerAllowed();
        _;
    }

    function _invalidTickerId(uint256 _id) internal pure {
        if (_id == 0) revert RaffleMarketplace__InvalidTickerId();
    }

    modifier invalidTickerId(uint256 _id) {
        _invalidTickerId(_id);
        _;
    }

    function _doesRaffleExists(uint256 id) internal view {
        if (_raffles[id].id == 0) revert RaffleMarketplace__RaffleNotCreated(id);
    }

    modifier doesRaffleExists(uint256 id) {
        _doesRaffleExists(id);
        _;
    }

    function _onlyRaffleHoster(uint256 id) internal view {
        if (msg.sender != _raffleHosterAddress[id]) {
            revert RaffleMarketplace__OnlyHosterAllowed(msg.sender, _raffleHosterAddress[id]);
        }
    }

    modifier onlyRaffleHoster(uint256 id) {
        _onlyRaffleHoster(id);
        _;
    }

    function _onlyRaffleContract(uint256 id) internal view {
        address raffleAddr = _raffles[id].raffleAddress;
        require(raffleAddr != address(0), "RaffleMarketplace: raffle not deployed");
        require(msg.sender == raffleAddr, "RaffleMarketplace: only raffle");
    }

    modifier onlyRaffleContract(uint256 id) {
        _onlyRaffleContract(id);
        _;
    }

    function doesRaffleStageExists(uint256 raffleId, RaffleLibrary.StageType stageType)
        public
        view
        returns (bool)
    {
        RaffleLibrary.RaffleStage[] memory stages = _raffleToRaffleStages[raffleId];
        for (uint256 i = 0; i < stages.length; i++) {
            if (stages[i].stageType == stageType) return true;
        }
        return false;
    }

    function _raffleStageExists(uint256 raffleId, RaffleLibrary.StageType stageType) internal view {
        if (!doesRaffleStageExists(raffleId, stageType)) {
            revert RaffleMarketplace__StageDoesNotExist(raffleId, stageType);
        }
    }

    modifier raffleStageExists(uint256 raffleId, RaffleLibrary.StageType stageType) {
        _raffleStageExists(raffleId, stageType);
        _;
    }

    function _raffleStageNotExists(uint256 raffleId, RaffleLibrary.StageType stageType) internal view {
        if (doesRaffleStageExists(raffleId, stageType)) {
            revert RaffleMarketplace__StageAlreadyExist(raffleId, stageType);
        }
    }

    modifier raffleStageNotExists(uint256 raffleId, RaffleLibrary.StageType stageType) {
        _raffleStageNotExists(raffleId, stageType);
        _;
    }

    function _isRaffleVerified(uint256 id) internal view {
        if (!_raffles[id].isVerifiedByMarketplace) revert RaffleMarketplace__RaffleNotVerified();
    }

    modifier isRaffleVerified(uint256 id) {
        _isRaffleVerified(id);
        _;
    }

    function _isRaffleNotVerified(uint256 id) internal view {
        if (_raffles[id].isVerifiedByMarketplace) revert RaffleMarketplace__RaffleVerified();
    }

    modifier isRaffleNotVerified(uint256 id) {
        _isRaffleNotVerified(id);
        _;
    }
}