//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../ERC721A/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RaffleNFT is ERC721A, Ownable, Pausable {
    // PRICE variable kept for compatibility (even though it's not used for minting here)
    uint256 public PRICE = 0 wei;

    string public baseTokenURI;
    address public raffleAddress;

    constructor(string memory baseURI, address _raffleAddress)
        ERC721A("Raffle NFT", "Lucky")
    {
        setBaseURI(baseURI);
        setRaffleAddress(_raffleAddress);
    }

    /* =========================  Admin controls  ========================= */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function setRaffleAddress(address _raffleAddress) public onlyOwner {
        raffleAddress = _raffleAddress;
    }

    function setPrice(uint256 _price) public onlyOwner {
        PRICE = _price;
    }

    /* =========================  Minting / burning  ========================= */

    /// @notice Mint a single NFT to `username`.
    /// @dev Kept the same signature and return values as the original.
    function mintNFTs(address username)
        public
        returns (bool transferred, uint256 mintedTokenId)
    {
        require(
            msg.sender == raffleAddress,
            "Not from a raffle contract call"
        );

        mintedTokenId = _mintSingleNFT(username);
        transferred = true;
    }

    function _mintSingleNFT(address username)
        private
        returns (uint256 newTokenID)
    {
        // In ERC721A, _nextTokenId() returns the ID that will be minted next.
        newTokenID = _nextTokenId();
        _safeMint(username, 1);
    }

    /// @notice Burn all NFTs owned by `owner`.
    /// @dev Kept same external behaviour as your original implementation.
    function burn(address owner) public {
        require(
            msg.sender == raffleAddress,
            "Not from a raffle contract call"
        );

        uint256[] memory tokenIds = tokensOfOwner(owner);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(tokenIds[i]);
        }
    }

    function burnAll() external onlyOwner {
        uint256 nextId = _nextTokenId();
        uint256 startId = _startTokenId();

        for (uint256 tokenId = startId; tokenId < nextId; tokenId++) {
            // _ownerOf(tokenId) returns address(0) if burned / never minted
            if (_ownerOf(tokenId) != address(0)) {
                _burn(tokenId);
            }
        }
    }

    /* =========================  Views / helpers  ========================= */

    /// @notice Returns all token IDs owned by `_owner`.
    /// @dev ERC721A does not provide Enumerable by default, so we derive this
    ///      by scanning existing token IDs up to _nextTokenId().
    function tokensOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 balance = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](balance);

        uint256 count = 0;
        uint256 nextId = _nextTokenId();
        uint256 startId = _startTokenId();

        for (uint256 tokenId = startId; tokenId < nextId && count < balance; tokenId++) {
            address ownerOfToken = _ownerOf(tokenId);
            if (ownerOfToken == _owner) {
                tokenIds[count] = tokenId;
                count++;
            }
        }

        // `count` should be equal to `balance`, but even if not, we still return the filled part.
        return tokenIds;
    }

    function _baseURI()
        internal
        view
        virtual
        override
        returns (string memory)
    {
        return baseTokenURI;
    }

    /// @notice Same behaviour as your original tokenURI: returns only baseURI.
    /// @dev Does NOT append tokenId to the URI, to preserve your current metadata scheme.
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? baseURI : "";
    }

    /// @notice Allow contract to receive ETH (for withdraw()).
    receive() external payable {}

    /// @notice Withdraw all ETH from the contract to the owner.
    function withdraw() public payable onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ether left to withdraw");

        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Transfer failed.");
    }

    /* =========================  Hooks / overrides  ========================= */

    /// @dev Enforce Pausable on all transfers, mints, and burns.
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override whenNotPaused {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Start token IDs from 1 to match the original Counters-based behaviour.
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }
}