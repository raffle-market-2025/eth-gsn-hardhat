// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./LibraryStruct.sol";
import "./IRaffleMarketplace.sol";
import "./IVerifier.sol";

error Marketplace__OnlyOwner();
error Marketplace__ZeroAddress();
error Marketplace__AlreadySet();
error Marketplace__VerifierNotSet();
error Marketplace__AutomationNotSet();
error Marketplace__NftImplNotSet();
error Marketplace__BadRaffleId();
error Marketplace__NotRaffle();

interface IRaffleAutomationConfig {
    function setAutomation(address automation) external;
}

interface IRaffleSetNft {
    function setRaffleNFT(address nft) external;
}

interface IRaffleNFTInit {
    function initialize(address raffleAddress_, string calldata baseURI_) external;
}

/**
 * RaffleMarketplace
 * - owner immutable (never changes)
 * - deploy raffle via Verifier (clones RaffleContract implementation)
 * - clones RaffleNFT from an implementation and initializes it (baseURI + raffleAddress)
 * - auto-wires raffle.setRaffleNFT(nft) and raffle.setAutomation(automation)
 * - view API for Automation: getNextTickerId(), getRaffleAddress(id)
 * - callbacks from RaffleContract: updateTicketsSold, updateCurrentOngoingStage, updateRaffleState, updateWinners
 */
contract RaffleMarketplace is IRaffleMarketplace {
    address public immutable owner;

    // raffle ids start at 1
    uint256 private raffleTicker;

    // infra addresses (set once)
    address public verifier;                // Verifier (Clones-based)
    address public automation;              // RaffleAutomationVRF
    address public raffleNftImplementation; // RaffleNFT implementation for clones

    struct RaffleRecord {
        address raffleAddress;
        address payable raffleOwner;
        address raffleNFT;
        RaffleLibrary.RaffleState state;
        RaffleLibrary.StageType currentStage;
        uint256 createdAt;
    }

    // raffleId => record
    mapping(uint256 => RaffleRecord) private raffles;

    // raffleId => stageType(uint256) => ticketsSold
    mapping(uint256 => mapping(uint256 => uint256)) private ticketsSoldByStage;

    // raffleId => buyer => total tickets bought (optional analytics)
    mapping(uint256 => mapping(address => uint256)) private ticketsBoughtByUser;

    // raffleId => winners
    mapping(uint256 => address payable[]) private winnersByRaffle;

    event VerifierSet(address indexed verifier);
    event AutomationSet(address indexed automation);
    event RaffleNftImplementationSet(address indexed nftImplementation);

    event RaffleCreated(uint256 indexed raffleId, address indexed raffleAddress, address indexed raffleOwner);
    event RaffleNftCloned(uint256 indexed raffleId, address indexed raffleNFT);

    // Mirrors updates coming from RaffleContract
    event RaffleStateUpdated(uint256 indexed raffleId, RaffleLibrary.RaffleState state);
    event RaffleStageUpdated(uint256 indexed raffleId, RaffleLibrary.StageType stage);
    event TicketsSoldUpdated(
        uint256 indexed raffleId,
        RaffleLibrary.StageType stage,
        uint256 amount,
        address indexed buyer
    );
    event WinnersUpdated(uint256 indexed raffleId, uint256 winnersCount);

    constructor() {
        owner = msg.sender;
        raffleTicker = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Marketplace__OnlyOwner();
        _;
    }

    modifier onlyRaffle(uint256 raffleId_) {
        address raffleAddr = raffles[raffleId_].raffleAddress;
        if (raffleAddr == address(0)) revert Marketplace__BadRaffleId();
        if (msg.sender != raffleAddr) revert Marketplace__NotRaffle();
        _;
    }

    /* =========================
       Infra one-time wiring
    ========================= */

    function setVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert Marketplace__ZeroAddress();
        if (verifier != address(0)) revert Marketplace__AlreadySet();
        verifier = _verifier;
        emit VerifierSet(_verifier);
    }

    function setAutomation(address _automation) external onlyOwner {
        if (_automation == address(0)) revert Marketplace__ZeroAddress();
        if (automation != address(0)) revert Marketplace__AlreadySet();
        automation = _automation;
        emit AutomationSet(_automation);
    }

    function setRaffleNftImplementation(address _nftImplementation) external onlyOwner {
        if (_nftImplementation == address(0)) revert Marketplace__ZeroAddress();
        if (raffleNftImplementation != address(0)) revert Marketplace__AlreadySet();
        raffleNftImplementation = _nftImplementation;
        emit RaffleNftImplementationSet(_nftImplementation);
    }

    /* =========================
       Automation view API
    ========================= */

    function getNextTickerId() external view returns (uint256) {
        return raffleTicker;
    }

    function getRaffleAddress(uint256 id) external view returns (address) {
        return raffles[id].raffleAddress;
    }

    /* =========================
       Create raffle (hoster entrypoint)
    ========================= */

    /**
     * @dev Creates RaffleContract via Verifier (Marketplace must be the caller, Verifier enforces onlyMarketplace).
     * Also clones + initializes ticket NFT (RaffleNFT) from raffleNftImplementation.
     * Finally sets trusted Automation caller on raffle.
     *
     * NOTE: nftName/nftSymbol kept for backward compatibility (ignored by clone-friendly NFT).
     */
    function createRaffle(
        uint256 durationSeconds,
        uint256 thresholdPercent,
        RaffleLibrary.RafflePrize[] calldata prizes_,
        RaffleLibrary.RaffleStage[] calldata stages_,
        string calldata nftBaseURI,
        string calldata /*nftName*/,
        string calldata /*nftSymbol*/
    ) external returns (uint256 raffleId, address raffleAddr) {
        _requireInfra();

        raffleId = raffleTicker;
        unchecked {
            raffleTicker = raffleId + 1;
        }

        raffleAddr = _deployViaVerifier(raffleId, durationSeconds, thresholdPercent, prizes_, stages_);
        emit RaffleCreated(raffleId, raffleAddr, msg.sender);

        address nft = _cloneInitAndWireNft(raffleAddr, nftBaseURI);
        emit RaffleNftCloned(raffleId, nft);

        // Strict wiring (если хотите best-effort — обернём в try/catch)
        IRaffleAutomationConfig(raffleAddr).setAutomation(automation);

        _storeRecord(raffleId, raffleAddr, nft, stages_);
    }

    function _requireInfra() internal view {
        if (verifier == address(0)) revert Marketplace__VerifierNotSet();
        if (automation == address(0)) revert Marketplace__AutomationNotSet();
        if (raffleNftImplementation == address(0)) revert Marketplace__NftImplNotSet();
    }

    function _deployViaVerifier(
        uint256 raffleId_,
        uint256 durationSeconds_,
        uint256 thresholdPercent_,
        RaffleLibrary.RafflePrize[] calldata prizes_,
        RaffleLibrary.RaffleStage[] calldata stages_
    ) internal returns (address raffleAddr) {
        // IMPORTANT: avoid struct literal => build step-by-step (reduces stack usage)
        IVerifier.toPassFunc memory data;

        data._raffleId = raffleId_;
        data._durationOfRaffle = durationSeconds_;
        data._threshold = thresholdPercent_;
        data._raffleOwner = payable(msg.sender);
        data._marketplceOwner = owner;

        // calldata -> memory copy
        data._prizes = prizes_;
        data._stages = stages_;

        raffleAddr = IVerifier(verifier).deployRaffle(data);
    }

    function _cloneInitAndWireNft(address raffleAddr, string calldata baseURI)
        internal
        returns (address nft)
    {
        nft = Clones.clone(raffleNftImplementation);
        IRaffleNFTInit(nft).initialize(raffleAddr, baseURI);
        IRaffleSetNft(raffleAddr).setRaffleNFT(nft);
    }

    function _storeRecord(
        uint256 raffleId_,
        address raffleAddr_,
        address nft_,
        RaffleLibrary.RaffleStage[] calldata stages_
    ) internal {
        RaffleRecord storage r = raffles[raffleId_];

        r.raffleAddress = raffleAddr_;
        r.raffleOwner = payable(msg.sender);
        r.raffleNFT = nft_;
        r.state = RaffleLibrary.RaffleState.OPEN;
        r.currentStage = stages_.length != 0 ? stages_[0].stageType : RaffleLibrary.StageType(0);
        r.createdAt = block.timestamp;
    }

    /* =========================
       Callbacks from RaffleContract (IRaffleMarketplace)
    ========================= */

    function updateTicketsSold(
        uint256 _raffleId,
        RaffleLibrary.StageType stageType,
        uint256 amount,
        address buyer
    ) external onlyRaffle(_raffleId) {
        ticketsSoldByStage[_raffleId][uint256(stageType)] += amount;
        ticketsBoughtByUser[_raffleId][buyer] += amount;
        emit TicketsSoldUpdated(_raffleId, stageType, amount, buyer);
    }

    function updateCurrentOngoingStage(uint256 _raffleId, RaffleLibrary.StageType stageType)
        external
        onlyRaffle(_raffleId)
    {
        raffles[_raffleId].currentStage = stageType;
        emit RaffleStageUpdated(_raffleId, stageType);
    }

    function updateRaffleState(uint256 _raffleId, RaffleLibrary.RaffleState newState)
        external
        onlyRaffle(_raffleId)
    {
        raffles[_raffleId].state = newState;
        emit RaffleStateUpdated(_raffleId, newState);
    }

    function updateWinners(uint256 _raffleId, address payable[] calldata winners_)
        external
        onlyRaffle(_raffleId)
    {
        delete winnersByRaffle[_raffleId];
        for (uint256 i = 0; i < winners_.length; ) {
            winnersByRaffle[_raffleId].push(winners_[i]);
            unchecked { ++i; }
        }
        emit WinnersUpdated(_raffleId, winners_.length);
    }

    /* =========================
       Frontend-oriented getters
    ========================= */

    function getOwner() external view returns (address) {
        return owner;
    }

    function getVerifier() external view returns (address) {
        return verifier;
    }

    function getAutomation() external view returns (address) {
        return automation;
    }

    function getRaffleNftImplementation() external view returns (address) {
        return raffleNftImplementation;
    }

    function getRaffleRecord(uint256 raffleId_)
        external
        view
        returns (
            address raffleAddress,
            address raffleOwner,
            address raffleNFT,
            RaffleLibrary.RaffleState state,
            RaffleLibrary.StageType currentStage,
            uint256 createdAt
        )
    {
        RaffleRecord storage r = raffles[raffleId_];
        if (r.raffleAddress == address(0)) revert Marketplace__BadRaffleId();
        return (r.raffleAddress, r.raffleOwner, r.raffleNFT, r.state, r.currentStage, r.createdAt);
    }

    function getTicketsSoldByStage(uint256 raffleId_, RaffleLibrary.StageType stageType) external view returns (uint256) {
        if (raffles[raffleId_].raffleAddress == address(0)) revert Marketplace__BadRaffleId();
        return ticketsSoldByStage[raffleId_][uint256(stageType)];
    }

    function getUserTicketsBought(uint256 raffleId_, address user) external view returns (uint256) {
        if (raffles[raffleId_].raffleAddress == address(0)) revert Marketplace__BadRaffleId();
        return ticketsBoughtByUser[raffleId_][user];
    }

    function getWinners(uint256 raffleId_) external view returns (address payable[] memory) {
        if (raffles[raffleId_].raffleAddress == address(0)) revert Marketplace__BadRaffleId();
        return winnersByRaffle[raffleId_];
    }
}