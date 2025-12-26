// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

/// @dev Minimal native-funding interface for VRF v2.5 Coordinator.
///      In VRF v2.5 subscriptions can be funded with native token in addition to LINK. :contentReference[oaicite:1]{index=1}
interface IVRFV2_5NativeFund {
    function fundSubscriptionWithNative(uint256 subId) external payable;
}

contract VRFV2SubscriptionManager {
    /* ========================= Errors ========================= */
    error OnlyOwner();
    error ZeroAddress();
    error ZeroAmount();
    error SubscriptionNotCreated();

    /* ========================= Events ========================= */
    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event SubscriptionCreated(uint256 indexed subId);
    event SubscriptionFundedLink(uint256 indexed subId, uint256 amount);
    event SubscriptionFundedNative(uint256 indexed subId, uint256 amount);
    event ConsumerAdded(uint256 indexed subId, address indexed consumer);
    event ConsumerRemoved(uint256 indexed subId, address indexed consumer);
    event SubscriptionCanceled(uint256 indexed subId, address indexed receivingWallet);

    /* ========================= Immutables ========================= */
    IVRFCoordinatorV2Plus public immutable COORDINATOR;
    LinkTokenInterface public immutable LINKTOKEN;

    /* ========================= State ========================= */
    address public owner;
    uint256 public s_subscriptionId;

    /* ========================= Constructor ========================= */
    constructor(address vrfCoordinator, address linkToken) {
        if (vrfCoordinator == address(0) || linkToken == address(0)) revert ZeroAddress();

        COORDINATOR = IVRFCoordinatorV2Plus(vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(linkToken);

        owner = msg.sender;

        _createNewSubscription();
    }

    /* ========================= Ownership ========================= */
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function updateOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnerUpdated(old, newOwner);
    }

    /* ========================= Subscription lifecycle ========================= */

    function _createNewSubscription() internal onlyOwner {
        // VRF v2.5 uses the same subscription concept, but supports both LINK and native balances. :contentReference[oaicite:2]{index=2}
        uint256 subId = COORDINATOR.createSubscription();
        s_subscriptionId = subId;

        // Add this contract as a consumer of its own subscription (optional, but convenient).
        COORDINATOR.addConsumer(subId, address(this));

        emit SubscriptionCreated(subId);
    }

    /// @notice Fund subscription with LINK.
    /// @dev Requires this contract to hold LINK.
    function topUpSubscriptionLink(uint256 amount) external onlyOwner {
        if (s_subscriptionId == 0) revert SubscriptionNotCreated();
        if (amount == 0) revert ZeroAmount();

        // Standard LINK funding: LINK.transferAndCall(Coordinator, amount, abi.encode(subId))
        LINKTOKEN.transferAndCall(address(COORDINATOR), amount, abi.encode(s_subscriptionId));

        emit SubscriptionFundedLink(s_subscriptionId, amount);
    }

    /// @notice Fund subscription with native token (e.g., Sepolia ETH).
    /// @dev Coordinator must support fundSubscriptionWithNative (VRF v2.5). :contentReference[oaicite:3]{index=3}
    function fundSubscriptionNative() external payable onlyOwner {
        if (s_subscriptionId == 0) revert SubscriptionNotCreated();
        if (msg.value == 0) revert ZeroAmount();

        IVRFV2_5NativeFund(address(COORDINATOR)).fundSubscriptionWithNative{value: msg.value}(s_subscriptionId);

        emit SubscriptionFundedNative(s_subscriptionId, msg.value);
    }

    function addConsumer(address consumerAddress) external onlyOwner {
        if (s_subscriptionId == 0) revert SubscriptionNotCreated();
        if (consumerAddress == address(0)) revert ZeroAddress();

        COORDINATOR.addConsumer(s_subscriptionId, consumerAddress);
        emit ConsumerAdded(s_subscriptionId, consumerAddress);
    }

    function removeConsumer(address consumerAddress) external onlyOwner {
        if (s_subscriptionId == 0) revert SubscriptionNotCreated();
        if (consumerAddress == address(0)) revert ZeroAddress();

        COORDINATOR.removeConsumer(s_subscriptionId, consumerAddress);
        emit ConsumerRemoved(s_subscriptionId, consumerAddress);
    }

    function cancelSubscription(address receivingWallet) external onlyOwner {
        if (s_subscriptionId == 0) revert SubscriptionNotCreated();
        if (receivingWallet == address(0)) revert ZeroAddress();

        COORDINATOR.cancelSubscription(s_subscriptionId, receivingWallet);

        emit SubscriptionCanceled(s_subscriptionId, receivingWallet);
        s_subscriptionId = 0;
    }

    /* ========================= Convenience views ========================= */

    function getSubscriptionId() external view returns (uint256) {
        return s_subscriptionId;
    }
}