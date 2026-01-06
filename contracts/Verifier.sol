// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./IVerifier.sol";
import "./LibraryStruct.sol";

error Verifier__ZeroAddress();
error Verifier__OnlyMarketplace();

interface IRaffleInit {
    function initialize(
        uint256 _raffleId,
        uint256 _durationOfRaffle,
        uint256 _threshold,
        address payable _raffleOwner,
        address _marketplceOwner,
        RaffleLibrary.RafflePrize[] calldata _prizes,
        RaffleLibrary.RaffleStage[] calldata _stages,
        address _marketplace
    ) external;
}

contract Verifier is IVerifier {
    address public immutable marketplace;
    address public immutable raffleImplementation;

    constructor(address _marketplace, address _raffleImplementation) {
        if (_marketplace == address(0) || _raffleImplementation == address(0)) revert Verifier__ZeroAddress();
        marketplace = _marketplace;
        raffleImplementation = _raffleImplementation;
    }

    function deployRaffle(toPassFunc memory data) external onlyMarketplace returns (address raffle) {
        raffle = Clones.clone(raffleImplementation);

        IRaffleInit(raffle).initialize(
            data._raffleId,
            data._durationOfRaffle,
            data._threshold,
            data._raffleOwner,
            data._marketplceOwner,
            data._prizes,
            data._stages,
            marketplace
        );
    }

    modifier onlyMarketplace() {
        if (msg.sender != marketplace) revert Verifier__OnlyMarketplace();
        _;
    }
}