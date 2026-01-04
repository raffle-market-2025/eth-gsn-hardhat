// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@opengsn/contracts/src/BasePaymaster.sol";

contract Paymaster is BasePaymaster {
    address public ourTarget;

    event TargetSet(address target);

    function setTarget(address target) external onlyOwner {
        require(target != address(0), "Paymaster: target=0");
        ourTarget = target;
        emit TargetSet(target);
    }

    function _preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata,   // signature (unused)
        bytes calldata,   // approvalData (unused)
        uint256           // maxPossibleGas (unused)
    )
        internal
        override
        returns (bytes memory context, bool rejectOnRecipientRevert)
    {
        // обязательная проверка для GSN v3:
        // forwarder должен быть "trusted" и paymaster'ом, и recipient'ом
        _verifyForwarder(relayRequest);

        address target = ourTarget;
        require(target != address(0), "Paymaster: target not set");
        require(relayRequest.request.to == target, "Paymaster: wrong target");

        // context можно использовать в postRelayedCall (логирование/учет)
        context = abi.encode(relayRequest.request.from);

        // Не платить, если recipient откатился (экономит депозит paymaster'а)
        rejectOnRecipientRevert = true;
    }

    function _postRelayedCall(
        bytes calldata,   // context (unused)
        bool,             // success (unused)
        uint256,          // gasUseWithoutPost (unused)
        GsnTypes.RelayData calldata // relayData (unused)
    ) internal override {
        // стандартная проверка BasePaymaster
        _verifyRelayHubOnly();

        // Обычно здесь НЕ стоит revert'ить: paymaster может быть списан за газ даже при revert.
        // Логи/учет — ок, но без жестких require.
    }

    function versionPaymaster() external pure override returns (string memory) {
        return "3.0.0";
    }
}