// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./LibraryStruct.sol";
import "./IRaffleMarketplace.sol";
import "./RaffleNFT.sol";

error Raffle__NotEnougEthEntered();
error Raffle__NotOpen();
error Raffle__OnlyHosterAllowed();
error Raffle__NotEnoughTicketsAvailable();
error Raffle__OnlyMarketplaceOwnerAllowed();
error Raffle__RaffleNotFinished();
error Raffle__NotReadyToDraw();
error Raffle__NotCalculating();

// --- Automation trust (Variant 1) ---
error Raffle__OnlyMarketplaceOrAutomation();
error Raffle__AutomationAlreadySet();
error Raffle__InvalidAutomation();

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

    // trusted Automation/VRF orchestrator (RaffleAutomationVRF.sol)
    address public automation;

    uint32 public noOfWinnersToPick;

    // NFT contract address for tickets
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

    event RaffleEntered(address indexed player);
    event WinnersPicked(address payable[] winners);
    event FundsReceived(address indexed from, uint256 amount);
    event CleanupProgress(uint256 from, uint256 to);

    // --- Automation wiring ---
    event AutomationSet(address indexed automation);

    constructor(
        uint256 _raffleId,
        uint256 _durationOfRaffle,
        uint256 _threshold,
        address payable _raffleOwner,
        address _marketplceOwner,
        RaffleLibrary.RafflePrize[] memory _prizes,
        RaffleLibrary.RaffleStage[] memory _stages,
        address _marketplace
    ) payable {
        require(_marketplace != address(0), "Raffle: marketplace address = 0");
        require(_raffleOwner != address(0), "Raffle: owner address = 0");
        require(_marketplceOwner != address(0), "Raffle: marketplaceOwner=0");

        raffleId = _raffleId;
        durationOfRaffle = block.timestamp + _durationOfRaffle;
        threshold = _threshold;
        raffleOwner = _raffleOwner;

        _addPrizeInStorage(_prizes);
        _addStageInStorage(_stages);

        noOfWinnersToPick = uint32(prizes.length);

        marketplaceOwner = _marketplceOwner;
        marketplace = _marketplace;
        raffleMarketplace = IRaffleMarketplace(_marketplace);

        s_raffleState = RaffleLibrary.RaffleState.OPEN;
    }

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    // ---------------------------------------------------------------------
    // Wiring: NFT + Automation (called by Marketplace / MarketplaceOwner)
    // ---------------------------------------------------------------------

    function createNftContract(
        string memory baseURI,
        string memory name_,
        string memory symbol_
    ) external onlyMarketplace {
        require(raffleNFT == address(0), "Raffle: NFT already set");
        RaffleNFT nft = new RaffleNFT(baseURI, address(this), name_, symbol_);
        raffleNFT = address(nft);
    }

    /// @notice Set trusted Automation/VRF orchestrator (only once).
    /// @dev Called by marketplaceOwner (EOA/admin) after deploying RaffleAutomationVRF.
    function setAutomation(address _automation) external onlyMarketplaceOwner {
        if (_automation == address(0)) revert Raffle__InvalidAutomation();
        if (automation != address(0)) revert Raffle__AutomationAlreadySet();
        automation = _automation;
        emit AutomationSet(_automation);
    }

    // ---------------------------------------------------------------------
    // Enter raffle
    // ---------------------------------------------------------------------

    function enterRaffle() external payable isRaffleOpen {
        require(raffleNFT != address(0), "Raffle: NFT not created");

        updateCurrentStage();
        RaffleLibrary.RaffleStage storage curStage = raffleStages[currentStage];

        if (msg.value < curStage.ticketPrice) revert Raffle__NotEnougEthEntered();

        uint256 ticketsBought = msg.value / curStage.ticketPrice;

        if (ticketsBought > (curStage.ticketsAvailable - curStage.ticketsSold)) {
            revert Raffle__NotEnoughTicketsAvailable();
        }

        // enforce max supply from stages
        require(tokensInRaffle.length + ticketsBought <= totalTickets(), "Raffle: sold out");

        curStage.ticketsSold += ticketsBought;

        for (uint256 i = 0; i < ticketsBought; i++) {
            (bool transferred, uint256 mintedTokenId) = RaffleNFT(raffleNFT).mintNFTs(msg.sender);
            require(transferred, "Raffle: mint failed");
            tokensInRaffle.push(RaffleLibrary.Players(curStage.ticketPrice, mintedTokenId));
        }

        // mirror to stages array for views
        for (uint256 i = 0; i < raffleStagesArray.length; i++) {
            if (raffleStagesArray[i].stageType == curStage.stageType) {
                raffleStagesArray[i].ticketsSold += ticketsBought;
            }
        }

        raffleMarketplace.updateTicketsSold(raffleId, curStage.stageType, ticketsBought, msg.sender);

        updateCurrentStage(); // (поведение оставлено как у вас)
        emit RaffleEntered(msg.sender);
    }

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

    // ---------------------------------------------------------------------
    // Marketplace/Automation-driven draw lifecycle (VRF seed -> keccak -> unique indices)
    // ---------------------------------------------------------------------

    function isReadyToDraw() public view returns (bool) {
        bool isOpen = (s_raffleState == RaffleLibrary.RaffleState.OPEN);
        bool isTimeFinished = (block.timestamp > durationOfRaffle);
        bool hasThreshold = isThresholdPassed();
        bool hasTickets = (tokensInRaffle.length > 0);
        return (isOpen && isTimeFinished && hasTickets && hasThreshold);
    }

    /// @notice Marketplace should request only 1 VRF word (seed).
    function getNumWords() external pure returns (uint32) {
        return 1;
    }

    function startDraw() external onlyMarketplace {
        if (!isReadyToDraw()) revert Raffle__NotReadyToDraw();
        s_raffleState = RaffleLibrary.RaffleState.CALCULATING;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);
    }

    function finalizeFromRandomWords(uint256[] calldata randomWords) external onlyMarketplace {
        if (s_raffleState != RaffleLibrary.RaffleState.CALCULATING) revert Raffle__NotCalculating();
        require(randomWords.length == 1, "Raffle: need 1 word");

        uint256 m = tokensInRaffle.length;
        require(m > 0, "Raffle: no tickets");

        uint256 k = noOfWinnersToPick;
        require(k > 0 && k <= m, "Raffle: bad k");

        // Domain separation: привязываем seed к конкретному raffle/контракту/объёму
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
        for (uint256 i = 0; i < k; i++) {
            uint256 tokenId = tokensInRaffle[idx[i]].id;
            winners[i] = payable(RaffleNFT(raffleNFT).ownerOf(tokenId));
        }

        // store and notify marketplace
        s_recentWinners = winners;
        raffleMarketplace.updateWinners(raffleId, winners);

        s_raffleState = RaffleLibrary.RaffleState.FINISHED;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);

        emit WinnersPicked(winners);

        // No O(m) burn here. Cleanup is batched.
    }

    function _pickUniqueTicketIndices(bytes32 seed, uint256 k, uint256 m)
        internal
        pure
        returns (uint256[] memory idx, bytes32 nextSeed)
    {
        require(k <= m, "k>m");
        idx = new uint256[](k);

        bytes32 s = seed;
        for (uint256 i = 0; i < k; i++) {
            while (true) {
                // seed evolves every attempt to avoid infinite loops on collisions
                s = keccak256(abi.encodePacked(s, i));
                uint256 cand = uint256(s) % m;

                bool dup = false;
                for (uint256 j = 0; j < i; j++) {
                    if (idx[j] == cand) { dup = true; break; }
                }
                if (!dup) { idx[i] = cand; break; }
            }
        }
        nextSeed = s;
    }

    // ---------------------------------------------------------------------
    // Batched cleanup: burn tickets by tokenId (cheap, no scanning)
    // ---------------------------------------------------------------------

    /// @notice Burn tickets in batches after FINISHED or REVERTED.
    /// @dev Call repeatedly until cleanupCursor == tokensInRaffle.length.
    function cleanupBurn(uint256 maxCount) external {
        require(
            s_raffleState == RaffleLibrary.RaffleState.FINISHED ||
            s_raffleState == RaffleLibrary.RaffleState.REVERTED,
            "Raffle: not finalized"
        );
        require(raffleNFT != address(0), "Raffle: NFT not created");
        require(maxCount > 0, "Raffle: maxCount=0");

        uint256 m = tokensInRaffle.length;
        uint256 from = s_cleanupCursor;
        if (from >= m) return;

        uint256 to = from + maxCount;
        if (to > m) to = m;

        uint256 count = to - from;
        uint256[] memory ids = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            ids[i] = tokensInRaffle[from + i].id;
        }

        // Effects then interaction (reverts roll back cursor anyway)
        s_cleanupCursor = to;

        RaffleNFT(raffleNFT).burnBatch(ids);

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
        require(s_raffleState == RaffleLibrary.RaffleState.OPEN, "Raffle: not open");

        // WARNING: O(m) transfers. For m=1000 could be heavy; consider batching.
        for (uint256 i = 0; i < tokensInRaffle.length; i++) {
            uint256 tokenId = tokensInRaffle[i].id;
            address payable ownerOfTicket = payable(RaffleNFT(raffleNFT).ownerOf(tokenId));
            ownerOfTicket.transfer(tokensInRaffle[i].ticketPrice);
        }

        s_raffleState = RaffleLibrary.RaffleState.REVERTED;
        raffleMarketplace.updateRaffleState(raffleId, s_raffleState);
    }

    function distributePrizes() public onlyMarketplaceOwner {
        if (s_raffleState != RaffleLibrary.RaffleState.FINISHED) revert Raffle__RaffleNotFinished();

        uint256 count = 0;
        for (uint256 i = 0; i < prizes.length; i++) {
            if (prizes[i].prizeAmount != 0 && count < s_recentWinners.length) {
                (bool sent, ) = payable(s_recentWinners[count]).call{value: prizes[i].prizeAmount}("");
                count++;
                require(sent, "Raffle: prize transfer failed");
            }
        }
    }

    function _sendFundsToMarketplace() external onlyMarketplaceOwner {
        (bool sent, ) = address(raffleMarketplace).call{value: address(this).balance}("");
        require(sent, "Raffle: send failed");
    }

    // ---------------------------------------------------------------------
    // Storage helpers
    // ---------------------------------------------------------------------

    function _addStageInStorage(RaffleLibrary.RaffleStage[] memory _stages) internal {
        require(_stages.length > 0, "Raffle: no stages");
        for (uint256 i = 0; i < _stages.length; i++) {
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

    function getCurrentThresholdValue() public view returns (uint256) {
        return (totalTicketsSold() * 100) / totalTickets();
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

    /// @dev Marketplace OR trusted automation contract
    modifier onlyMarketplace() {
        if (msg.sender != marketplace && msg.sender != automation) {
            revert Raffle__OnlyMarketplaceOrAutomation();
        }
        _;
    }
}