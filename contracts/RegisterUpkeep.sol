// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// UpkeepIDConsumerExample.sol imports functions from both ./AutomationRegistryInterface1_2.sol and
// ./interfaces/LinkTokenInterface.sol

import { LinkTokenInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

/**
* THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
* THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
* DO NOT USE THIS CODE IN PRODUCTION.
*/

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

contract RaffleRegisterUpkeep {
  LinkTokenInterface public immutable i_link;
  address public immutable registrar;
  
  bytes4 registerSig = KeeperRegistrarInterface.register.selector;

  constructor(
    address _link,
    address _registrar
 
  ) {
    i_link = LinkTokenInterface(_link);
    registrar = _registrar;

  }

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
    
    i_link.transferAndCall(registrar, amount, bytes.concat(registerSig, payload));
 
  }
}
