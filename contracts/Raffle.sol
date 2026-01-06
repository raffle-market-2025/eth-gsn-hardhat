// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./LibraryStruct.sol";
import "./IRaffleMarketplace.sol";

/* ========= Minimal NFT interface (no import of full RaffleNFT bytecode) ========= */
interface IRaffleNFT {
    function mintNFTs(address to) external returns (bool transferred, uint256 mintedTokenId);
    function burnBatch(uint256[] calldata tokenIds) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

error Raffle__NotEnougEthEntered();
error Raffle__NotOpen();
error Raffle__OnlyHosterAllowed();
error Raffle__NotEnoughTicketsAvailable();
error Raffle__OnlyMarketplaceOwnerAllowed();
error Raffle__RaffleNotFinished();
error Raffle__NotReadyToDraw();
error Raffle__NotCalculating();

error Raffle__ZeroAddress();
error Raffle__NftNotSet();
error Raffle__NftAlreadySet();
error Raffle__AutomationAlreadySet();
error Raffle__OnlyAuthorizedCaller();
error Raffle__BadRandomWords();
error Raffle__BadWinnersCount();
error Raffle__NotFinalized();
error Raffle__MaxCountZero();
error Raffle__AlreadyInitialized();

contract RaffleContract {
    IRaffleMarketplace public raffleMarketplace;

    // stageType(uint) => stage data
    mapping(uint256 => RaffleLibrary.RaffleStage) private raffleStages;
    RaffleLibrary.RaffleStage[] private raffleStagesArray;

    uint256 public raffleId;
    uint256 public durationOfRaffle; // end timestamp
    uint256 public threshold;        // percent threshold

    address payable public raffleOwner;
    address public marketplaceOwner;
    address public marketplace;

    // Trusted automation contract (RaffleAutomationVRF). Set once by marketplace.
    address public automation;

    uint32 public noOfWinnersToPick;

    // Ticket NFT (cloned/deployed by Marketplace). Set once.
    address public raffleNFT;

    // ticket list (id + ticketPrice for refunds)
    RaffleLibrary.Players[] private tokensInRaffle;

    // state machine
    RaffleLibrary.RaffleState private s_raffleState;
    uint256 private currentStage;

    // winners (повтор адресов допускается)
    address payable[] private s_recentWinners;

    // prizes storage
    RaffleLibrary.RafflePrize[] private prizes;

    // cleanup cursor for batch burns
    uint256 private s_cleanupCursor;

    // optional: last derived seed (for trace/debug)
    bytes32 private s_seed;

    bool private s_initialized;

    event RaffleEntered(address indexed player);
    event WinnersPicked(address payable[] winners);
    event FundsReceived(address indexed from, uint256 amount);
    event CleanupProgress(uint256 from, uint256 to);
    event AutomationSet(address indexed automation);
    event RaffleNFTSet(address indexed raffleNFT);

    // ---------------------------------------------------------------------
    // Initializer (replaces constructor for clones)
    // ---------------------------------------------------------------------
    function initialize(
        uint256 _raffleId,
        uint256 _durationOfRaffle,
        uint256 _threshold,
        address payable _raffleOwner,
        address _marketplceOwner,
        RaffleLibrary.RafflePrize[] calldata _prizes,
        RaffleLibrary.RaffleStage[] calldata _stages,
        address _marketplace
    ) external {
        if (s_initialized) revert Raffle__AlreadyInitialized();
        s_initialized = true;

        if (_marketplace == address(0) || _raffleOwner == address(0) || _marketplceOwner == address(0)) {
            revert Raffle__ZeroAddress();
        }

        raffleId = _raffleId;
        durationOfRaffle = block.timestamp + _durationOfRaffle;
        threshold = _threshold;
        raffleOwner = _raffleOwner;

        marketplaceOwner = _marketplceOwner;
        marketplace = _marketplace;
        raffleMarketplace = IRaffleMarketplace(_marketplace);

        _addPrizeInStorage(_prizes);
        _addStageInStorage(_stages);

        noOfWinnersToPick = uint32(prizes.length);

        s_raffleState = RaffleLibrary.RaffleState.OPEN;
    }

    receive() external payable { emit FundsReceived(msg.sender, msg.value); }
    fallback() external payable { emit FundsReceived(msg.sender, msg.value); }

    // ---------------------------------------------------------------------
    // Wiring (called by Marketplace)
    // ---------------------------------------------------------------------

    function setAutomation(address _automation) external onlyMarketplace {
        if (_automation == address(0)) revert Raffle__ZeroAddress();
        if (automation != address(0)) revert Raffle__AutomationAlreadySet();
        automation = _automation;
        emit AutomationSet(_automation);
    }

    function setRaffleNFT(address _raffleNFT) external onlyMarketplace {
        if (_raffleNFT == address(0)) revert Raffle__ZeroAddress();
        if (raffleNFT != address(0)) revert Raffle__NftAlreadySet();
        raffleNFT = _raffleNFT;
        emit RaffleNFTSet(_raffleNFT);
    }

    // ---------------------------------------------------------------------
    // Enter raffle
    // ---------------------------------------------------------------------

    function enterRaffle() external payable isRaffleOpen {
        address nft = raffleNFT;
        if (nft == address(0)) revert Raffle__NftNotSet();

        updateCurrentStage();
        RaffleLibrary.RaffleStage storage curStage = raffleStages[currentStage];

        if (msg.value < curStage.ticketPrice) revert Raffle__NotEnougEthEntered();

        uint256 ticketsBought = msg.value / curStage.ticketPrice;

        if (ticketsBought > (curStage.ticketsAvailable - curStage.ticketsSold)) {
            revert Raffle__NotEnoughTicketsAvailable();
        }

        // enforce max supply from stages (mint guard)
        if (tokensInRaffle.length + ticketsBought > totalTickets()) {
            revert Raffle__NotEnoughTicketsAvailable();
        }

        curStage.ticketsSold += ticketsBought;

        for (uint256 i = 0; i < ticketsBought; ) {
            (bool transferred, uint256 mintedTokenId) = IRaffleNFT(nft).mintNFTs(msg.sender);
            if (!transferred) revert Raffle__NotEnougEthEntered();
            tokensInRaffle.push(RaffleLibrary.Players(curStage.ticketPrice, mintedTokenId));
            unchecked { ++i; }
        }

        // mirror to stages array for views
        for (uint256 i = 0; i < raffleStagesArray.length; ) {
            if (raffleStagesArray[i].stageType == curStage.stageType) {
                raffleStagesArray[i].ticketsSold += ticketsBought;
                break;
            }
            unchecked { ++i; }
        }

        raffleMarketplace.updateTicketsSold(raffleId, curStage.stageType, ticketsBought, msg.sender);

        // keep your original behavior
        updateCurrentStage();

        emit RaffleEntered(msg.sender);
    }

    function updateCurrentStage() internal {
        if (raffleStages[currentStage].ticketsSold != raffleStages[currentStage].ticketsAvailable) return;

        uint256 nextStageType;
        for (uint256 i = 0; i < raffleStagesArray.length; ) {
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
            unchecked { ++i; }
        }
    }

    // ---------------------------------------------------------------------
    // Draw lifecycle
    // ---------------------------------------------------------------------

    function isReadyToDraw() public view returns (bool) {
        bool isOpen = (s_raffleState == RaffleLibrary.RaffleState.OPEN);
        bool isTimeFinished = (block.timestamp > durationOfRaffle);
        bool hasThreshold = isThresholdPassed();
        bool hasTickets = (tokensInRaffle.length > 0);
        return (isOpen && isTimeFinished && hasTickets && hasThreshold);
    }

    function getNumWords() external pure returns (uint32) {
        return 1;
    }

    function startDraw() external onlyAuthorized {
        if (!isReadyToDraw()) revert Raffle__NotReadyToDraw();
        s_raffleState = RaffleLibrary.RaffleState.CALCULATING;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);
    }

    function finalizeFromRandomWords(uint256[] calldata randomWords) external onlyAuthorized {
        if (s_raffleState != RaffleLibrary.RaffleState.CALCULATING) revert Raffle__NotCalculating();
        if (randomWords.length != 1) revert Raffle__BadRandomWords();

        uint256 m = tokensInRaffle.length;
        if (m == 0) revert Raffle__BadWinnersCount();

        uint256 k = noOfWinnersToPick;
        if (k == 0 || k > m) revert Raffle__BadWinnersCount();

        address nft = raffleNFT;
        if (nft == address(0)) revert Raffle__NftNotSet();

        // Domain separation: seed is bound to this raffle + contract + sample size
        bytes32 seed = keccak256(
            abi.encodePacked(
                bytes32(randomWords[0]),
                address(this),
                raffleId,
                m
            )
        );

        (uint256[] memory idx, bytes32 nextSeed) = _pickUniqueTicketIndices(seed, k, m);
        s_seed = nextSeed;

        address payable[] memory winners = new address payable[](k);
        for (uint256 i = 0; i < k; ) {
            uint256 tokenId = tokensInRaffle[idx[i]].id;
            winners[i] = payable(IRaffleNFT(nft).ownerOf(tokenId));
            unchecked { ++i; }
        }

        s_recentWinners = winners;
        raffleMarketplace.updateWinners(raffleId, winners);

        s_raffleState = RaffleLibrary.RaffleState.FINISHED;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);

        emit WinnersPicked(winners);
    }

    function _pickUniqueTicketIndices(bytes32 seed, uint256 k, uint256 m)
        internal
        pure
        returns (uint256[] memory idx, bytes32 nextSeed)
    {
        idx = new uint256[](k);

        bytes32 s = seed;
        for (uint256 i = 0; i < k; ) {
            while (true) {
                s = keccak256(abi.encodePacked(s, i));
                uint256 cand = uint256(s) % m;

                bool dup = false;
                for (uint256 j = 0; j < i; ) {
                    if (idx[j] == cand) { dup = true; break; }
                    unchecked { ++j; }
                }
                if (!dup) { idx[i] = cand; break; }
            }
            unchecked { ++i; }
        }
        nextSeed = s;
    }

    // ---------------------------------------------------------------------
    // Batched cleanup
    // ---------------------------------------------------------------------

    function cleanupBurn(uint256 maxCount) external {
        if (
            s_raffleState != RaffleLibrary.RaffleState.FINISHED &&
            s_raffleState != RaffleLibrary.RaffleState.REVERTED
        ) revert Raffle__NotFinalized();

        address nft = raffleNFT;
        if (nft == address(0)) revert Raffle__NftNotSet();
        if (maxCount == 0) revert Raffle__MaxCountZero();

        uint256 m = tokensInRaffle.length;
        uint256 from = s_cleanupCursor;
        if (from >= m) return;

        uint256 to = from + maxCount;
        if (to > m) to = m;

        uint256 count = to - from;
        uint256[] memory ids = new uint256[](count);

        for (uint256 i = 0; i < count; ) {
            ids[i] = tokensInRaffle[from + i].id;
            unchecked { ++i; }
        }

        s_cleanupCursor = to;

        IRaffleNFT(nft).burnBatch(ids);

        emit CleanupProgress(from, to);
    }

    function cleanupCursor() external view returns (uint256) {
        return s_cleanupCursor;
    }

    function cleanupRemaining() external view returns (uint256) {
        uint256 m = tokensInRaffle.length;
        if (s_cleanupCursor >= m) return 0;
        return m - s_cleanupCursor;
    }

    // ---------------------------------------------------------------------
    // Refund / prizes
    // ---------------------------------------------------------------------

    function revertLottery() external onlyHoster onlyMarketplaceOwner {
        if (s_raffleState != RaffleLibrary.RaffleState.OPEN) revert Raffle__NotOpen();

        address nft = raffleNFT;
        if (nft == address(0)) revert Raffle__NftNotSet();

        for (uint256 i = 0; i < tokensInRaffle.length; ) {
            uint256 tokenId = tokensInRaffle[i].id;
            address payable ownerOfTicket = payable(IRaffleNFT(nft).ownerOf(tokenId));
            ownerOfTicket.transfer(tokensInRaffle[i].ticketPrice);
            unchecked { ++i; }
        }

        s_raffleState = RaffleLibrary.RaffleState.REVERTED;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);
    }

    function distributePrizes() public onlyMarketplaceOwner {
        if (s_raffleState != RaffleLibrary.RaffleState.FINISHED) revert Raffle__RaffleNotFinished();

        uint256 count = 0;
        for (uint256 i = 0; i < prizes.length && count < s_recentWinners.length; ) {
            uint256 amt = prizes[i].prizeAmount;
            if (amt != 0) {
                (bool sent, ) = payable(s_recentWinners[count]).call{value: amt}("");
                if (!sent) revert Raffle__NotEnougEthEntered();
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }
    }

    function _sendFundsToMarketplace() external onlyMarketplaceOwner {
        (bool sent, ) = address(raffleMarketplace).call{value: address(this).balance}("");
        if (!sent) revert Raffle__NotEnougEthEntered();
    }

    // ---------------------------------------------------------------------
    // Storage helpers
    // ---------------------------------------------------------------------

    function _addStageInStorage(RaffleLibrary.RaffleStage[] calldata _stages) internal {
        if (_stages.length == 0) revert Raffle__NotEnougEthEntered();
        for (uint256 i = 0; i < _stages.length; ) {
            raffleStages[uint256(_stages[i].stageType)] = RaffleLibrary.RaffleStage(
                _stages[i].stageType,
                _stages[i].ticketsAvailable,
                _stages[i].ticketPrice,
                0
            );

            raffleStagesArray.push(
                RaffleLibrary.RaffleStage(
                    _stages[i].stageType,
                    _stages[i].ticketsAvailable,
                    _stages[i].ticketPrice,
                    0
                )
            );

            unchecked { ++i; }
        }
        currentStage = uint256(_stages[0].stageType);
    }

    function _addPrizeInStorage(RaffleLibrary.RafflePrize[] calldata _prizes) internal {
        for (uint256 i = 0; i < _prizes.length; ) {
            prizes.push(
                RaffleLibrary.RafflePrize(
                    _prizes[i].prizeTitle,
                    _prizes[i].country,
                    _prizes[i].prizeAmount
                )
            );
            unchecked { ++i; }
        }
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getEntraceFee() external view returns (uint256) {
        return raffleStages[currentStage].ticketPrice;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return tokensInRaffle.length;
    }

    function getRecentWinners() external view returns (address payable[] memory) {
        return s_recentWinners;
    }

    function getCurrentStage() external view returns (RaffleLibrary.RaffleStage memory) {
        return raffleStages[currentStage];
    }

    function getStages() external view returns (RaffleLibrary.RaffleStage[] memory) {
        return raffleStagesArray;
    }

    function getStageInformation(uint256 stageType) external view returns (RaffleLibrary.RaffleStage memory) {
        return raffleStages[stageType];
    }

    function getCurrentState() external view returns (RaffleLibrary.RaffleState) {
        return s_raffleState;
    }

    function totalTicketsSold() public view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < raffleStagesArray.length; ) {
            count += raffleStagesArray[i].ticketsSold;
            unchecked { ++i; }
        }
        return count;
    }

    function totalTickets() public view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < raffleStagesArray.length; ) {
            count += raffleStagesArray[i].ticketsAvailable;
            unchecked { ++i; }
        }
        return count;
    }

    function getCurrentThresholdValue() public view returns (uint256) {
        uint256 tt = totalTickets();
        if (tt == 0) return 0;
        return (totalTicketsSold() * 100) / tt;
    }

    function isThresholdPassed() public view returns (bool) {
        return (getCurrentThresholdValue() >= threshold);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getSeed() external view returns (bytes32) {
        return s_seed;
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier isRaffleOpen() {
        if (s_raffleState != RaffleLibrary.RaffleState.OPEN) revert Raffle__NotOpen();
        _;
    }

    modifier onlyHoster() {
        if (msg.sender != raffleOwner) revert Raffle__OnlyHosterAllowed();
        _;
    }

    modifier onlyMarketplaceOwner() {
        if (msg.sender != marketplaceOwner) revert Raffle__OnlyMarketplaceOwnerAllowed();
        _;
    }

    modifier onlyMarketplace() {
        if (msg.sender != marketplace) revert Raffle__OnlyAuthorizedCaller();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != marketplace && msg.sender != automation) revert Raffle__OnlyAuthorizedCaller();
        _;
    }
}