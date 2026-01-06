// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract RaffleNFT is ERC721 {
    /* =========================  Errors  ========================= */
    error NotRaffle();
    error RaffleZeroAddress();
    error AlreadyInitialized();
    error NonexistentToken();

    /* =========================  Storage (per-clone)  ========================= */
    address public raffleAddress;
    string private baseTokenURI;
    uint256 private nextTokenId;
    bool private initialized;

    /* =========================  Constructor (implementation only)  ========================= */
    // Constructor runs only for the implementation contract, NOT for clones.
    // We keep it empty-ish. Name/symbol are provided via overrides below.
    constructor() ERC721("", "") {}

    /* =========================  Init (for clones)  ========================= */
    function initialize(address raffleAddress_, string calldata baseURI_) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        if (raffleAddress_ == address(0)) revert RaffleZeroAddress();
        raffleAddress = raffleAddress_;
        baseTokenURI = baseURI_;
        nextTokenId = 1; // start IDs from 1
    }

    /* =========================  Modifiers  ========================= */
    modifier onlyRaffle() {
        if (msg.sender != raffleAddress) revert NotRaffle();
        _;
    }

    /* =========================  name/symbol (same for all clones)  ========================= */
    function name() public pure override returns (string memory) {
        return "Raffle Ticket";
    }

    function symbol() public pure override returns (string memory) {
        return "LUCK";
    }

    /* =========================  Mint / burn  ========================= */
    function mintNFTs(address to)
        external
        onlyRaffle
        returns (bool transferred, uint256 mintedTokenId)
    {
        mintedTokenId = nextTokenId;
        unchecked { nextTokenId = mintedTokenId + 1; }

        _mint(to, mintedTokenId);
        transferred = true;
    }

    function burnToken(uint256 tokenId) external onlyRaffle {
        _burn(tokenId);
    }

    function burnBatch(uint256[] calldata tokenIds) external onlyRaffle {
        for (uint256 i = 0; i < tokenIds.length; ) {
            _burn(tokenIds[i]);
            unchecked { ++i; }
        }
    }

    /* =========================  Metadata  ========================= */
    /// @dev Keep your behavior: return only baseTokenURI (no tokenId appended).
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // OZ ERC721 exposes _ownerOf internally (v5+), cheap existence check
        if (_ownerOf(tokenId) == address(0)) revert NonexistentToken();
        return baseTokenURI;
    }
}