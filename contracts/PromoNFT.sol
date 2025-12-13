//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract PromoRaffleNFTs is ERC721Enumerable, Ownable, Pausable {
    using SafeMath for uint256;
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;
    
    uint public PRICE = 0 wei;

    string public baseTokenURI;
    address public promoRaffleAddress;

    constructor(string memory baseURI, address _promoRaffleAddress) ERC721("Promo Raffle NFT", "PromoRaffle") {
        setBaseURI(baseURI);
        setPromoRaffleAddress(_promoRaffleAddress);
        _tokenIds.increment();
    }
	
	function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }


    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function setPromoRaffleAddress(address _promoRaffleAddress) public onlyOwner {
        promoRaffleAddress = _promoRaffleAddress;
    }
	
	function setPrice(uint _price) public onlyOwner {
       PRICE = _price;
    }

    function mintNFTs(address username) public returns(bool transferred, uint mintedTokenId) {
        require(msg.sender == promoRaffleAddress, "Not a raffle contract call");
        mintedTokenId = _mintSingleNFT(username);
        transferred = true;
    }

    function _mintSingleNFT(address username) private returns(uint newTokenID) {
        newTokenID = _tokenIds.current();
        _safeMint(username, newTokenID);
        _tokenIds.increment();
    }

    function tokensOfOwner(address _owner) public view returns (uint[] memory) {
        uint tokenCount = balanceOf(_owner);
        uint[] memory tokensId = new uint256[](tokenCount);

        for (uint i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    function withdraw() public payable onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0, "No ether left to withdraw");
        (bool success, ) = (msg.sender).call{value: balance}("");
        require(success, "Transfer failed.");
    }

    // function isApprovedForAll(
    //    address _owner,
    //    address _operator
    // ) public override view returns (bool isOperator) {
    //    return ERC721.isApprovedForAll(_owner, _operator);
    // }

    function burn(address owner) public {
        require(msg.sender == promoRaffleAddress, "Not a raffle contract call");
        uint[] memory tokenIds = tokensOfOwner(owner);

        for (uint i = 0; i < tokenIds.length; i++) {
           _burn(tokenIds[i]); 
        }
    }
	
	function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    //
    // The following functions are overrides required by Solidity.
    //

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI)) : "";
    }

    // function transferFrom(
    //    address from,
    //    address to,
    //    uint256 tokenId
    // ) public virtual override {
    //    require(to == promoRaffleAddress, "ERC721: transfer forbidden");
    //    require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
    //
    //    _transfer(from, to, tokenId);
    // }

    // function safeTransferFrom(
    //    address from,
    //    address to,
    //    uint256 tokenId
    // ) public virtual override {
    //    require(to == promoRaffleAddress, "ERC721: transfer forbidden");
    //    safeTransferFrom(from, to, tokenId, "");
    // }

    // function safeTransferFrom(
    //    address from,
    //    address to,
    //    uint256 tokenId,
    //    bytes memory data
    // ) public virtual override {
    //    require(to == promoRaffleAddress, "ERC721: transfer forbidden");
    //    require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
    //    _safeTransfer(from, to, tokenId, data);
    // }
}