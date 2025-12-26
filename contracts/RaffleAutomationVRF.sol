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

error AutomVRF__OnlyOwner(); // оставляем имя, но теперь это "admin"
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
 */
contract RaffleAutomationVRF is
    VRFConsumerBaseV2Plus,
    AutomationCompatibleInterface,
    RaffleRegisterUpkeep
{
    /* ========= Admin / Config ========= */

    // PATCH: rename to avoid collision with ConfirmedOwnerWithProposal.owner()
    address public admin;

    IRaffleMarketplaceView public marketplace;

    // VRF v2.5
    IVRFCoordinatorV2Plus public coordinator; // typed coordinator
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

        // PATCH
        admin = msg.sender;

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

    // PATCH: rename modifier to avoid future collisions
    modifier onlyAdmin() {
        if (msg.sender != admin) revert AutomVRF__OnlyOwner();
        _;
    }

    /* ========= Admin setters ========= */

    function updateOwner(address newOwner) external onlyAdmin {
        admin = newOwner;
    }

    function setMarketplace(address newMarketplace) external onlyAdmin {
        if (newMarketplace == address(0)) revert AutomVRF__BadConfig();
        marketplace = IRaffleMarketplaceView(newMarketplace);
        emit MarketplaceUpdated(newMarketplace);
    }

    function setVRFConfig(
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit
    ) external onlyAdmin {
        if (_vrfCoordinator == address(0)) revert AutomVRF__BadConfig();
        if (_subscriptionId == 0) revert AutomVRF__BadConfig();

        coordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;

        emit VRFConfigUpdated(_vrfCoordinator, _subscriptionId, _keyHash, _callbackGasLimit);
    }

    function setLowWatermarkWei(uint96 newLowWatermarkWei) external onlyAdmin {
        lowWatermarkWei = newLowWatermarkWei;
    }

    function setScanCursor(uint256 newCursor) external onlyAdmin {
        scanCursor = newCursor;
        emit CursorUpdated(newCursor);
    }

    // Rescue: clear a stuck inFlight flag (if something went wrong operationally)
    function clearInFlight(uint256 raffleId) external onlyAdmin {
        inFlight[raffleId] = false;
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
     * Emits SubscriptionFunded.
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
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 next = marketplace.getNextTickerId();
        if (next <= 1) return (false, bytes(""));
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

            if (raffleAddr != address(0) && !inFlight[id]) {
                if (IRaffleFinalize(raffleAddr).isReadyToDraw()) {
                    tmp[found] = id;
                    found++;
                }
            }

            unchecked { ++scanned; }
            id = (id == last) ? 1 : (id + 1);
        }

        if (found == 0) return (false, bytes(""));

        uint256[] memory batch = new uint256[](found);
        for (uint256 i = 0; i < found; ) {
            batch[i] = tmp[i];
            unchecked { ++i; }
        }

        uint256 nextCursor = id;

        upkeepNeeded = true;
        performData = abi.encode(batch, nextCursor);
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint256[] memory batch, uint256 nextCursor) = abi.decode(performData, (uint256[], uint256));

        uint256 next = marketplace.getNextTickerId();
        if (next <= 1) revert AutomVRF__NoRaffles();
        uint256 last = next - 1;

        // update cursor
        if (nextCursor < 1 || nextCursor > last) {
            scanCursor = 1;
        } else {
            scanCursor = nextCursor;
        }
        emit CursorUpdated(scanCursor);

        // lock raffles; skip ones that changed since checkUpkeep
        uint256[] memory locked = new uint256[](batch.length);
        uint256 lockedCount = 0;

        for (uint256 i = 0; i < batch.length; ) {
            uint256 raffleId = batch[i];
            address raffleAddr = marketplace.getRaffleAddress(raffleId);

            if (raffleAddr != address(0) && !inFlight[raffleId]) {
                // If startDraw reverts (not ready anymore / already calculating), skip.
                try IRaffleFinalize(raffleAddr).startDraw() {
                    inFlight[raffleId] = true;
                    locked[lockedCount] = raffleId;
                    unchecked { ++lockedCount; }
                } catch {
                    // skipped
                }
            }

            unchecked { ++i; }
        }

        if (lockedCount == 0) revert AutomVRF__UpkeepNotNeeded();

        // Request ONE VRF word (nativePayment=true)
        uint256 requestId = coordinator.requestRandomWords(
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
        for (uint256 i = 0; i < lockedCount; ) {
            store.push(locked[i]);
            unchecked { ++i; }
        }

        // shrink for event
        uint256[] memory out = new uint256[](lockedCount);
        for (uint256 i = 0; i < lockedCount; ) {
            out[i] = locked[i];
            unchecked { ++i; }
        }

        emit BatchLocked(requestId, out);

        // Emit low-watermark alert (best-effort, non-blocking)
        _emitLowWatermarkIfNeeded();
    }

    /* ========= VRF callback ========= */

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256[] storage batch = requestIdToBatch[requestId];
        uint256 n = batch.length;

        if (n == 0) {
            // safest: ignore unknown (do not revert VRF callback)
            return;
        }

        uint256 base = randomWords[0];

        // PATCH: allocate once (fixes "undeclared identifier / uninitialized array")
        uint256[] memory one;

        for (uint256 i = 0; i < n; ) {
            uint256 raffleId = batch[i];
            address raffleAddr = marketplace.getRaffleAddress(raffleId);

            // release lock regardless (to avoid perma-stuck)
            inFlight[raffleId] = false;

            if (raffleAddr != address(0)) {
                // per-raffle derived word (domain separation)
                one[0] = uint256(keccak256(abi.encodePacked(base, requestId, raffleId, raffleAddr)));

                try IRaffleFinalize(raffleAddr).finalizeFromRandomWords(one) {
                    emit RaffleFinalized(requestId, raffleId);
                } catch (bytes memory reason) {
                    emit RaffleFinalizeFailed(requestId, raffleId, reason);
                }
            }

            unchecked { ++i; }
        }

        delete requestIdToBatch[requestId];
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
     */
    function registerThisUpkeep(
        string memory name,
        uint32 gasLimit,
        uint96 amount, // registrar funding (usually LINK)
        uint8 source
    ) external onlyAdmin {
        bytes memory empty;
        registerAndPredictID(name, empty, address(this), gasLimit, admin, empty, amount, source);
    }

    /* ========= Optional: expose request batches for debugging ========= */

    function getRequestBatch(uint256 requestId) external view returns (uint256[] memory) {
        return requestIdToBatch[requestId];
    }
}