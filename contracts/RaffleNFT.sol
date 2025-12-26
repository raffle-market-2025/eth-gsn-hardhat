// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../ERC721A/ERC721A.sol";

contract RaffleNFT is ERC721A {
    /* =========================  Errors  ========================= */

    error NotRaffle();
    error RaffleZeroAddress();
    error NonexistentToken();

    /* =========================  Immutable config  ========================= */

    address public immutable raffleAddress;
    string private baseTokenURI;

    /* =========================  Constructor  ========================= */

    constructor(
        string memory baseURI_,
        address raffleAddress_,
        string memory name_,
        string memory symbol_
    ) ERC721A(name_, symbol_) {
        if (raffleAddress_ == address(0)) revert RaffleZeroAddress();
        raffleAddress = raffleAddress_;
        baseTokenURI = baseURI_;
    }

    /* =========================  Modifiers  ========================= */

    modifier onlyRaffle() {
        if (msg.sender != raffleAddress) revert NotRaffle();
        _;
    }

    /* =========================  Mint / burn  ========================= */

    function mintNFTs(address to)
        external
        onlyRaffle
        returns (bool transferred, uint256 mintedTokenId)
    {
        mintedTokenId = _nextTokenId();
        _mint(to, 1); // cheaper than _safeMint
        transferred = true;
    }

    function burnToken(uint256 tokenId) external onlyRaffle {
        _burn(tokenId); // ERC721A v4.3.0: _burn(tokenId,false)
    }

    function burnBatch(uint256[] calldata tokenIds) external onlyRaffle {
        for (uint256 i = 0; i < tokenIds.length; ) {
            _burn(tokenIds[i]);
            unchecked { ++i; }
        }
    }

    /* =========================  Metadata  ========================= */

    /// @dev Keep your behavior: return only baseTokenURI (no tokenId appended).
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert NonexistentToken();
        return baseTokenURI;
    }

    /// @dev Start token IDs from 1 (matches your earlier behavior).
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }
}