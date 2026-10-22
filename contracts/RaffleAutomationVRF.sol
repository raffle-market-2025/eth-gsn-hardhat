// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./RegisterUpkeep.sol";

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

import {VRFConsumerBaseV2Plus} from
    "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from
    "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from
    "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/* ========= Interfaces ========= */

interface IRaffleMarketplaceView {
    function getNextTickerId() external view returns (uint256);
    function getRaffleAddress(uint256 id) external view returns (address);
}

interface IRaffleFinalize {
    function isReadyToDraw() external view returns (bool);
    function startDraw() external;
    function finalizeFromRandomWords(uint256[] calldata randomWords) external;
}

/**
 * VRF v2.5 coordinator native funding entrypoint.
 * Coordinator accepts native token to fund subscription.
 */
interface IVRFV2_5NativeFund {
    function fundSubscriptionWithNative(uint256 subId) external payable;
}

/**
 * VRF v2.5 subscription read API (includes nativeBalance).
 */
interface IVRFV2_5SubscriptionView {
    function getSubscription(uint256 subId)
        external
        view
        returns (
            uint96 balance,           // LINK balance (may be 0 for native-only)
            uint96 nativeBalance,     // native token balance (ETH on Sepolia)
            uint64 reqCount,
            address owner,
            address[] memory consumers
        );
}

/* ========= Errors ========= */

error AutomVRF__BadConfig();
error AutomVRF__NoRaffles();
error AutomVRF__UpkeepNotNeeded();
error AutomVRF__ZeroValue();

/**
 * RaffleAutomationVRF
 * - One upkeep contract for all raffles
 * - VRF v2.5 subscription, native payment
 * - Batch-ready processing with bounded scan + bounded batch size
 * - Optional nativeBalance low-watermark alert (event-only, serverless)
 * - Optional native subscription funding helper (fundSubscriptionNative)
 *
 * IMPORTANT:
 * - Uses owner mechanics from VRFConsumerBaseV2Plus (ConfirmedOwnerWithProposal).
 *   Do NOT declare `address public owner` here (it would collide with owner()).
 */
contract RaffleAutomationVRF is
    VRFConsumerBaseV2Plus,
    AutomationCompatibleInterface,
    RaffleRegisterUpkeep
{
    /* ========= Config ========= */

    IRaffleMarketplaceView public marketplace;

    // VRF v2.5 (typed coordinator)
    IVRFCoordinatorV2Plus public coordinator;
    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit;

    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    // Low-watermark for native balance (wei). If 0 => disabled.
    uint96 public lowWatermarkWei;

    // Batch knobs
    uint8 public immutable MAX_BATCH;
    uint16 public immutable MAX_SCAN;

    /* ========= State ========= */

    // scan cursor in [1..last]
    uint256 public scanCursor;

    // raffleId -> currently locked/in-flight under a VRF request
    mapping(uint256 => bool) public inFlight;

    // requestId -> raffleIds batch
    mapping(uint256 => uint256[]) private requestIdToBatch;
    mapping(uint256 => uint256) public requestRandomWord;
    mapping(uint256 => bool) public requestFulfilled;
    mapping(uint256 => mapping(uint256 => address)) public requestRaffle;
    mapping(uint256 => mapping(uint256 => bool)) public raffleFinalized;
    uint256 public pendingRaffles;
    mapping(uint256 => uint256) public raffleRequest;
    event RandomnessReceived(uint256 indexed requestId);

    /* ========= Events ========= */

    event CursorUpdated(uint256 newCursor);
    event BatchLocked(uint256 indexed requestId, uint256[] raffleIds);
    event RaffleFinalized(uint256 indexed requestId, uint256 indexed raffleId);
    event RaffleFinalizeFailed(uint256 indexed requestId, uint256 indexed raffleId, bytes reason);

    event VRFConfigUpdated(address coordinator, uint256 subId, bytes32 keyHash, uint32 callbackGasLimit);
    event MarketplaceUpdated(address marketplace);

    // REQUIRED BY YOU:
    event SubscriptionFunded(address indexed from, uint256 indexed subId, uint256 amount);

    event VRFNativeLowWatermark(uint256 indexed subId, uint96 nativeBalance, uint96 lowWatermarkWei);

    /* ========= Constructor ========= */

    constructor(
        address _marketplace,
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        address _linkTokenForRegistrar,
        address _registrar,
        uint8 _maxBatch,
        uint16 _maxScan
    )
        VRFConsumerBaseV2Plus(_vrfCoordinator)
        RaffleRegisterUpkeep(_linkTokenForRegistrar, _registrar)
    {
        if (_marketplace == address(0)) revert AutomVRF__BadConfig();
        if (_vrfCoordinator == address(0)) revert AutomVRF__BadConfig();
        if (_subscriptionId == 0) revert AutomVRF__BadConfig();
        if (_maxBatch == 0) revert AutomVRF__BadConfig();
        if (_maxScan == 0) revert AutomVRF__BadConfig();

        marketplace = IRaffleMarketplaceView(_marketplace);
        coordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);

        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;

        MAX_BATCH = _maxBatch;
        MAX_SCAN = _maxScan;

        scanCursor = 1;

        emit MarketplaceUpdated(_marketplace);
        emit VRFConfigUpdated(_vrfCoordinator, _subscriptionId, _keyHash, _callbackGasLimit);
    }

    /* ========= Admin setters (uses base onlyOwner) ========= */

    function setMarketplace(address newMarketplace) external onlyOwner {
        if (newMarketplace == address(0)) revert AutomVRF__BadConfig();
        require(pendingRaffles == 0, "Pending raffles");
        marketplace = IRaffleMarketplaceView(newMarketplace);
        emit MarketplaceUpdated(newMarketplace);
    }

    function setVRFConfig(
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit
    ) external onlyOwner {
        if (_vrfCoordinator == address(0)) revert AutomVRF__BadConfig();
        if (_subscriptionId == 0) revert AutomVRF__BadConfig();

        require(pendingRaffles == 0, "Pending raffles");
        s_vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        coordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;

        emit VRFConfigUpdated(_vrfCoordinator, _subscriptionId, _keyHash, _callbackGasLimit);
    }

    function setLowWatermarkWei(uint96 newLowWatermarkWei) external onlyOwner {
        lowWatermarkWei = newLowWatermarkWei;
    }

    function setScanCursor(uint256 newCursor) external onlyOwner {
        scanCursor = newCursor;
        emit CursorUpdated(newCursor);
    }

    /* ========= VRF subscription views ========= */

    function getSubscriptionNativeBalance() public view returns (uint96 nativeBalance) {
        (, nativeBalance, , , ) =
            IVRFV2_5SubscriptionView(address(coordinator)).getSubscription(subscriptionId);
    }

    function getSubscriptionInfo()
        external
        view
        returns (uint96 linkBalance, uint96 nativeBalance, uint64 reqCount, address subOwner, uint256 consumersCount)
    {
        address[] memory consumers;
        (linkBalance, nativeBalance, reqCount, subOwner, consumers) =
            IVRFV2_5SubscriptionView(address(coordinator)).getSubscription(subscriptionId);
        consumersCount = consumers.length;
    }

    /* ========= Native subscription funding helper ========= */

    /**
     * Allows anyone to fund the VRF v2.5 subscription with native token (ETH on Sepolia).
     * Emits SubscriptionFunded and (optionally) low-watermark alert.
     */
    function fundSubscriptionNative() external payable {
        if (msg.value == 0) revert AutomVRF__ZeroValue();

        IVRFV2_5NativeFund(address(coordinator)).fundSubscriptionWithNative{value: msg.value}(subscriptionId);
        emit SubscriptionFunded(msg.sender, subscriptionId, msg.value);

        _emitLowWatermarkIfNeeded();
    }

    /* ========= Automation ========= */

    /**
     * One upkeep for all raffles: checkData ignored.
     * Returns performData = abi.encode(batchIds, nextCursor)
     */
    function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory) {
        (uint256[] memory batch, uint256 cursor, bool advance) = _scan();
        return (batch.length > 0 || advance, abi.encode(batch, cursor));
    }

    function _scan() internal view returns (uint256[] memory batch, uint256 nextCursor, bool advance) {
        uint256 next = marketplace.getNextTickerId();
        if (next <= 1) return (new uint256[](0), 1, false);
        uint256 last = next - 1;

        uint256 cursor = scanCursor;
        if (cursor < 1 || cursor > last) cursor = 1;

        uint256[] memory tmp = new uint256[](uint256(MAX_BATCH));
        uint256 found = 0;

        uint256 scanned = 0;
        uint256 id = cursor;

        uint256 scanLimit = uint256(MAX_SCAN);
        if (scanLimit > last) scanLimit = last;

        while (scanned < scanLimit && found < uint256(MAX_BATCH)) {
            address raffleAddr = marketplace.getRaffleAddress(id);

            if (inFlight[id] && requestFulfilled[raffleRequest[id]]) {
                tmp[found++] = id;
            } else if (raffleAddr != address(0) && !inFlight[id]) {
                try IRaffleFinalize(raffleAddr).isReadyToDraw() returns (bool ready) {
                    if (ready) tmp[found++] = id;
                } catch {}
            }

            scanned++;
            id = (id == last) ? 1 : (id + 1);
        }

        batch = new uint256[](found);
        for (uint256 i = 0; i < found; i++) batch[i] = tmp[i];

        return (batch, id, scanLimit < last);
    }

    // performData is advisory; rescan current state to enforce MAX_SCAN/MAX_BATCH and cursor integrity.
    function performUpkeep(bytes calldata) external override {
        (uint256[] memory batch, uint256 nextCursor, bool advance) = _scan();
        if (batch.length == 0 && !advance) revert AutomVRF__UpkeepNotNeeded();
        uint256 last = marketplace.getNextTickerId() - 1;

        // update cursor
        if (nextCursor < 1 || nextCursor > last) scanCursor = 1;
        else scanCursor = nextCursor;

        emit CursorUpdated(scanCursor);
        if (batch.length == 0) return;

        // lock raffles; skip ones that changed since checkUpkeep
        uint256[] memory locked = new uint256[](batch.length);
        uint256 lockedCount = 0;

        for (uint256 i = 0; i < batch.length; i++) {
            uint256 raffleId = batch[i];
            address raffleAddr = marketplace.getRaffleAddress(raffleId);

            if (raffleAddr == address(0)) continue;
            if (inFlight[raffleId]) {
                uint256 pendingRequest = raffleRequest[raffleId];
                if (requestFulfilled[pendingRequest]) {
                    try this.finalizeRaffle(pendingRequest, raffleId) {} catch (bytes memory reason) {
                        emit RaffleFinalizeFailed(pendingRequest, raffleId, reason);
                    }
                }
                continue;
            }

            // If startDraw reverts (not ready anymore / already calculating), skip.
            try IRaffleFinalize(raffleAddr).startDraw() {
                inFlight[raffleId] = true;
                locked[lockedCount] = raffleId;
                lockedCount++;
            } catch {
                // skipped
            }
        }

        if (lockedCount == 0) return;

        // Request ONE VRF word (nativePayment=true)
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );

        // Persist batch under requestId
        uint256[] storage store = requestIdToBatch[requestId];
        for (uint256 i = 0; i < lockedCount; i++) {
            store.push(locked[i]);
            raffleRequest[locked[i]] = requestId;
            requestRaffle[requestId][locked[i]] = marketplace.getRaffleAddress(locked[i]);
        }
        pendingRaffles += lockedCount;

        // shrink for event
        uint256[] memory out = new uint256[](lockedCount);
        for (uint256 i = 0; i < lockedCount; i++) out[i] = locked[i];

        emit BatchLocked(requestId, out);

        // Optional low-watermark alert (best-effort)
        _emitLowWatermarkIfNeeded();
    }

    /* ========= VRF callback ========= */

    /// @dev Keep the charged callback small: persist randomness before any fallible finalization.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (requestIdToBatch[requestId].length == 0 || requestFulfilled[requestId] || randomWords.length != 1) return;
        requestRandomWord[requestId] = randomWords[0];
        requestFulfilled[requestId] = true;
        emit RandomnessReceived(requestId);
    }

    /// @notice Anyone can retry with the original VRF word; failed attempts never request new randomness.
    function finalizeRaffle(uint256 requestId, uint256 raffleId) external {
        address raffleAddr = requestRaffle[requestId][raffleId];
        require(requestFulfilled[requestId] && raffleAddr != address(0), "Randomness unavailable");
        require(!raffleFinalized[requestId][raffleId], "Already finalized");
        uint256[] memory one = new uint256[](1);
        one[0] = uint256(keccak256(abi.encodePacked(requestRandomWord[requestId], requestId, raffleId, raffleAddr)));
        // Revert preserves retryability, including when the raffle runs out of gas.
        raffleFinalized[requestId][raffleId] = true;
        IRaffleFinalize(raffleAddr).finalizeFromRandomWords(one);
        inFlight[raffleId] = false;
        pendingRaffles--;
        emit RaffleFinalized(requestId, raffleId);
    }

    /* ========= Internal helpers ========= */

    function _emitLowWatermarkIfNeeded() internal {
        if (lowWatermarkWei == 0) return;

        uint96 nb;
        try IVRFV2_5SubscriptionView(address(coordinator)).getSubscription(subscriptionId)
            returns (uint96, uint96 nativeBalance, uint64, address, address[] memory)
        {
            nb = nativeBalance;
        } catch {
            return;
        }

        if (nb < lowWatermarkWei) {
            emit VRFNativeLowWatermark(subscriptionId, nb, lowWatermarkWei);
        }
    }

    /* ========= Convenience: upkeep registration ========= */

    /**
     * Register ONE Automation upkeep for this contract (global).
     * checkData is empty by design (batch scan happens internally).
     *
     * NOTE:
     * - Uses base owner() from ConfirmedOwnerWithProposal via VRFConsumerBaseV2Plus.
     */
    function registerThisUpkeep(
        string memory name,
        uint32 gasLimit,
        uint96 amount, // registrar funding (often LINK; depends on registrar config)
        uint8 source
    ) external onlyOwner {
        bytes memory empty;
        registerAndPredictID(name, empty, address(this), gasLimit, owner(), empty, amount, source);
    }

    /* ========= Optional: expose request batches for debugging ========= */

    function getRequestBatch(uint256 requestId) external view returns (uint256[] memory) {
        return requestIdToBatch[requestId];
    }
}