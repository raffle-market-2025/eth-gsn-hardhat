// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./RegisterUpkeep.sol";
import "./LibraryStruct.sol";

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/* ========= Interfaces ========= */

interface IRaffleMarketplaceView {
    function getNextTickerId() external view returns (uint256);
    function getRaffleAddress(uint256 id) external view returns (address);
}

interface IRaffleCleanup {
    function getCurrentState() external view returns (RaffleLibrary.RaffleState);
    function cleanupRemaining() external view returns (uint256);
    function cleanupBurn(uint256 maxCount) external;
}

/* ========= Errors ========= */

error Cleanup__OnlyOwner();
error Cleanup__BadConfig();
error Cleanup__UpkeepNotNeeded();

/**
 * RaffleCleanupAutomation
 * - One Automation upkeep for all raffles cleanup
 * - Scans marketplace raffles (bounded), selects those with cleanupRemaining() > 0 and state FINISHED/REVERTED
 * - Calls cleanupBurn(PER_RAFFLE_BURN) per selected raffle
 *
 * Notes:
 * - Automation still needs LINK funding (registrar)
 * - No servers required
 */
contract RaffleCleanupAutomation is AutomationCompatibleInterface, RaffleRegisterUpkeep {
    address public owner;
    IRaffleMarketplaceView public marketplace;

    // How many raffles to process per upkeep
    uint8 public immutable MAX_BATCH;

    // How many raffles to scan per checkUpkeep
    uint16 public immutable MAX_SCAN;

    // burn batch size per raffle per upkeep call
    uint16 public immutable PER_RAFFLE_BURN;

    // round-robin scan cursor
    uint256 public scanCursor;

    event MarketplaceUpdated(address indexed marketplace);
    event CursorUpdated(uint256 newCursor);

    event CleanupBatch(uint256[] raffleIds);
    event CleanupAttempt(uint256 indexed raffleId, uint256 remainingBefore, uint256 burnMax);
    event CleanupFailed(uint256 indexed raffleId, bytes reason);

    constructor(
        address _marketplace,
        address _linkTokenForRegistrar,
        address _registrar,
        uint8 _maxBatch,
        uint16 _maxScan,
        uint16 _perRaffleBurn
    ) RaffleRegisterUpkeep(_linkTokenForRegistrar, _registrar) {
        if (_marketplace == address(0)) revert Cleanup__BadConfig();
        if (_maxBatch == 0) revert Cleanup__BadConfig();
        if (_maxScan == 0) revert Cleanup__BadConfig();
        if (_perRaffleBurn == 0) revert Cleanup__BadConfig();

        owner = msg.sender;
        marketplace = IRaffleMarketplaceView(_marketplace);

        MAX_BATCH = _maxBatch;
        MAX_SCAN = _maxScan;
        PER_RAFFLE_BURN = _perRaffleBurn;

        scanCursor = 1;

        emit MarketplaceUpdated(_marketplace);
        emit CursorUpdated(scanCursor);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Cleanup__OnlyOwner();
        _;
    }

    function updateOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function setMarketplace(address newMarketplace) external onlyOwner {
        if (newMarketplace == address(0)) revert Cleanup__BadConfig();
        marketplace = IRaffleMarketplaceView(newMarketplace);
        emit MarketplaceUpdated(newMarketplace);
    }

    function setScanCursor(uint256 newCursor) external onlyOwner {
        scanCursor = newCursor;
        emit CursorUpdated(newCursor);
    }

    /**
     * checkUpkeep finds up to MAX_BATCH raffles that need cleanup.
     * performData = abi.encode(raffleIds, nextCursor)
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 next = marketplace.getNextTickerId();
        if (next <= 1) return (false, bytes("")); // no raffles
        uint256 last = next - 1;

        uint256 cursor = scanCursor;
        if (cursor < 1 || cursor > last) cursor = 1;

        uint256[] memory tmp = new uint256[](MAX_BATCH);
        uint256 found = 0;

        uint256 scanned = 0;
        uint256 id = cursor;

        uint256 scanLimit = MAX_SCAN;
        if (scanLimit > last) scanLimit = last;

        while (scanned < scanLimit && found < MAX_BATCH) {
            address raffleAddr = marketplace.getRaffleAddress(id);

            if (raffleAddr != address(0)) {
                // Any revert on a broken raffle should not break the upkeep
                try IRaffleCleanup(raffleAddr).getCurrentState() returns (RaffleLibrary.RaffleState st) {
                    if (st == RaffleLibrary.RaffleState.FINISHED || st == RaffleLibrary.RaffleState.REVERTED) {
                        try IRaffleCleanup(raffleAddr).cleanupRemaining() returns (uint256 rem) {
                            if (rem > 0) {
                                tmp[found] = id;
                                found++;
                            }
                        } catch {
                            // ignore
                        }
                    }
                } catch {
                    // ignore
                }
            }

            scanned++;
            id = (id == last) ? 1 : (id + 1);
        }

        if (found == 0) return (false, bytes(""));

        uint256[] memory batch = new uint256[](found);
        for (uint256 i = 0; i < found; i++) batch[i] = tmp[i];

        uint256 nextCursor = id;

        upkeepNeeded = true;
        performData = abi.encode(batch, nextCursor);
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint256[] memory batch, uint256 nextCursor) = abi.decode(performData, (uint256[], uint256));

        uint256 next = marketplace.getNextTickerId();
        if (next <= 1) revert Cleanup__UpkeepNotNeeded();
        uint256 last = next - 1;

        // update cursor
        if (nextCursor < 1 || nextCursor > last) scanCursor = 1;
        else scanCursor = nextCursor;
        emit CursorUpdated(scanCursor);

        bool didWork = false;

        for (uint256 i = 0; i < batch.length; i++) {
            uint256 raffleId = batch[i];
            address raffleAddr = marketplace.getRaffleAddress(raffleId);
            if (raffleAddr == address(0)) continue;

            // Re-check in performUpkeep (state may change between check & perform)
            try IRaffleCleanup(raffleAddr).getCurrentState() returns (RaffleLibrary.RaffleState st) {
                if (st != RaffleLibrary.RaffleState.FINISHED && st != RaffleLibrary.RaffleState.REVERTED) {
                    continue;
                }
            } catch {
                continue;
            }

            uint256 remaining;
            try IRaffleCleanup(raffleAddr).cleanupRemaining() returns (uint256 rem) {
                remaining = rem;
            } catch {
                continue;
            }
            if (remaining == 0) continue;

            didWork = true;
            emit CleanupAttempt(raffleId, remaining, PER_RAFFLE_BURN);

            // Call cleanupBurn; if it reverts (e.g., NFT burn issues), continue other raffles
            try IRaffleCleanup(raffleAddr).cleanupBurn(PER_RAFFLE_BURN) {
                // ok
            } catch (bytes memory reason) {
                emit CleanupFailed(raffleId, reason);
            }
        }

        if (!didWork) revert Cleanup__UpkeepNotNeeded();
        emit CleanupBatch(batch);
    }

    /**
     * Convenience: register one global upkeep for this cleanup worker.
     * Needs LINK to be transferred to registrar (Automation registrar).
     */
    function registerThisUpkeep(
        string memory name,
        uint32 gasLimit,
        uint96 amount,
        uint8 source
    ) external onlyOwner {
        bytes memory empty;
        registerAndPredictID(name, empty, address(this), gasLimit, owner, empty, amount, source);
    }
}