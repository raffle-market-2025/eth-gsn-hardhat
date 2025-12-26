// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

interface KeeperRegistrarInterface {
    function register(
        string memory name,
        bytes calldata encryptedEmail,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes calldata checkData,
        uint96 amount,
        uint8 source,
        address sender
    ) external;
}

error Upkeep__ZeroRegistrar();
error Upkeep__ZeroLink();
error Upkeep__ZeroUpkeepContract();
error Upkeep__ZeroAdmin();
error Upkeep__EmptyName();
error Upkeep__ZeroAmount();

contract RaffleRegisterUpkeep {
    LinkTokenInterface public immutable i_link;
    address public immutable registrar;

    bytes4 private constant REGISTER_SIG = KeeperRegistrarInterface.register.selector;

    constructor(address _link, address _registrar) {
        if (_link == address(0)) revert Upkeep__ZeroLink();
        if (_registrar == address(0)) revert Upkeep__ZeroRegistrar();

        i_link = LinkTokenInterface(_link);
        registrar = _registrar;
    }

    /// @notice Registers an upkeep via registrar using LINK.transferAndCall
    /// @dev New approach expects:
    ///      - upkeepContract = Marketplace
    ///      - checkData = abi.encode(raffleId)
    function registerAndPredictID(
        string memory name,
        bytes memory encryptedEmail,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes memory checkData,
        uint96 amount,
        uint8 source
    ) public {
        if (bytes(name).length == 0) revert Upkeep__EmptyName();
        if (upkeepContract == address(0)) revert Upkeep__ZeroUpkeepContract();
        if (adminAddress == address(0)) revert Upkeep__ZeroAdmin();
        if (amount == 0) revert Upkeep__ZeroAmount();
        // optional: allow empty checkData if you ever want a single upkeep for all raffles
        // if (checkData.length == 0) revert Upkeep__EmptyCheckData();

        bytes memory payload = abi.encode(
            name,
            encryptedEmail,
            upkeepContract,
            gasLimit,
            adminAddress,
            checkData,
            amount,
            source,
            address(this)
        );

        i_link.transferAndCall(registrar, amount, bytes.concat(REGISTER_SIG, payload));
    }
}