// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@opengsn/contracts/src/BasePaymaster.sol";

contract PaymasterWhitelist is BasePaymaster {
    error TargetNotSet();
    error WrongTarget();
    error MethodNotAllowed();
    error ValueNotSupported();

    address public target;

    // selector => allowed
    mapping(bytes4 => bool) public allowed;

    event TargetSet(address indexed target);
    event SelectorSet(bytes4 indexed selector, bool allowed);

    // ---- Common selectors (for convenience / clarity) ----
    // PromoRaffle.enterRaffle(string,bytes3)
    bytes4 public constant ENTER_RAFFLE =
        bytes4(keccak256("enterRaffle(string,bytes3)"));

    // RMT.buyTokens()
    bytes4 public constant BUY_TOKENS =
        bytes4(keccak256("buyTokens()"));

    function setTarget(address _target) external onlyOwner {
        target = _target;
        emit TargetSet(_target);
    }

    /// @notice Allow/deny a single function selector.
    function setAllowed(bytes4 selector, bool isAllowed) external onlyOwner {
        allowed[selector] = isAllowed;
        emit SelectorSet(selector, isAllowed);
    }

    /// @notice Allow/deny a batch of selectors.
    function setAllowedBatch(bytes4[] calldata selectors, bool isAllowed) external onlyOwner {
        for (uint256 i = 0; i < selectors.length; i++) {
            allowed[selectors[i]] = isAllowed;
            emit SelectorSet(selectors[i], isAllowed);
        }
    }

    /// @notice One-call setup for PromoRaffle: set target + allow enterRaffle only.
    function configurePromoRaffle(address promoRaffle) external onlyOwner {
        target = promoRaffle;
        emit TargetSet(promoRaffle);

        // strict allowlist: only enterRaffle
        allowed[ENTER_RAFFLE] = true;
        emit SelectorSet(ENTER_RAFFLE, true);

        // explicitly deny buyTokens (not necessary, but makes intent explicit)
        allowed[BUY_TOKENS] = false;
        emit SelectorSet(BUY_TOKENS, false);
    }

    function _preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata, /* signature */
        bytes calldata, /* approvalData */
        uint256 /* maxPossibleGas */
    )
        internal
        override
        returns (bytes memory context, bool rejectOnRecipientRevert)
    {
        address _target = target;
        if (_target == address(0)) revert TargetNotSet();
        if (relayRequest.request.to != _target) revert WrongTarget();

        // GSN meta-tx should not be used to send ETH value
        if (relayRequest.request.value != 0) revert ValueNotSupported();

        bytes calldata data = relayRequest.request.data;

        // no selector => deny (covers receive/fallback and malformed calls)
        if (data.length < 4) revert MethodNotAllowed();

        bytes4 sel = bytes4(data[0:4]);
        if (!allowed[sel]) revert MethodNotAllowed();

        // context can be empty; you can also encode sender if you need it in postRelayedCall
        return ("", false);
    }

    function _postRelayedCall(
        bytes calldata, /* context */
        bool, /* success */
        uint256, /* gasUseWithoutPost */
        GsnTypes.RelayData calldata /* relayData */
    ) internal override {
        // no-op
    }

    function versionPaymaster() external pure override returns (string memory) {
        return "3.0.0";
    }
}