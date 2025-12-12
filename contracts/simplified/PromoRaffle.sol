// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

error Raffle__NotEnoughEthEntered();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__ManyTicketsOnWallet();
error Raffle__upkeepNotNeeded(uint256 currentBalance, uint256 noPlayers, uint256 RaffleState);

contract PromoRaffle is ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    address payable[] private s_players;
    uint[] private tokensInRaffle;
    address private s_recentWinner;
    uint256 private s_lastTimestamp;
    uint256 private s_cycles = 0;
    address public owner;
    // address promoNft;
    // address promoNftSender;
    uint public maxSupply;

    RaffleState private s_raffleState;

    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(address payable[], uint256 s_cycles);
    event WinnerPicked(address indexed winner, uint256 s_cycles);

    constructor(
        string memory _name,
        string memory _symbol,
        uint _maxSupply
    ) ERC721(_name, _symbol) {
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
        maxSupply = _maxSupply;
        owner = _msgSender();
        s_cycles = s_cycles + 1;
    }

    // Mint a single NFT to `to`
    function mint(address to) internal returns (uint256) {
        require(_tokenIdCounter.current() < maxSupply, "Max supply reached");
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        _tokenIdCounter.increment();
        return tokenId;
    }

    // Burn an NFT by tokenId
    function burn(uint256 tokenId) internal {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        _burn(tokenId);
    }

    function enterRaffle() public {
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        uint tokenCount = address(this).balance;
        // PromoRaffleNFTs(promoNft).balanceOf(_msgSender());
        if (tokenCount > 0) {
            revert Raffle__ManyTicketsOnWallet();
        }
        uint256 mintedTokenId = mint(_msgSender());
        // (bool transferred, uint mintedTokenId) = PromoRaffleNFTs(promoNft).mintNFTs(_msgSender());
        // require(transferred, "Can't transfer");
        tokensInRaffle.push(mintedTokenId);
        emit RaffleEnter(_msgSender());
    }

    // function promoRafflesToSubscribers(address receiver) public {
    //     require(_msgSender() == promoNftSender, "No access");
    //     uint mintedTokenId = PromoRaffleNFTs(promoNft).mint(receiver);
    //     // (bool transferred, uint mintedTokenId) = PromoRaffleNFTs(promoNft).mintNFTs(receiver);
    //     // require(transferred, "Can't transfer");
    //     tokensInRaffle.push(mintedTokenId);
    //     emit RaffleEnter(receiver);
    // }

    function checkSet() public view returns (bool upkeepNeeded) {
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        bool hasPlayers = (tokensInRaffle.length > maxSupply);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && hasPlayers && hasBalance);
    }

    function runRaffle() external onlyOwner {
        bool upkeepNeeded = checkSet();
        if (!upkeepNeeded) {
            revert Raffle__upkeepNotNeeded(
                address(this).balance,
                tokensInRaffle.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;

        for (uint i = 0; i < tokensInRaffle.length; i++) {
            s_players.push(payable(ownerOf(tokensInRaffle[i])));
        }

        emit RequestedRaffleWinner(s_players, s_cycles);

        // Generate pseudo-random number using blockhash and timestamp
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, blockhash(block.number - 1))));
        pickWinner(randomNumber, s_cycles);
    }

    function pickWinner(uint256 randomNumber, uint256 _s_cycles) internal {
        uint256 indexOfWinner = randomNumber % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_cycles = s_cycles + 1;
        s_lastTimestamp = block.timestamp;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        s_raffleState = RaffleState.OPEN;

        emit WinnerPicked(recentWinner, _s_cycles);

        for (uint i = 0; i < tokensInRaffle.length; i++) {
            burn(tokensInRaffle[i]);
            // PromoRaffleNFTs(promoNft).burn(s_players[i]);
        }
        
        while (s_players.length > 0) {
            s_players.pop();
            tokensInRaffle.pop();
        }
    }

    function getTokensIds() public view returns (uint[] memory) {
        return tokensInRaffle;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return tokensInRaffle.length;
    }

    function getLatestTimestamp() public view returns (uint256) {
        return s_lastTimestamp;
    }

    function updatePlayersNeeded(uint _maxSupply) public onlyOwner {
        maxSupply = _maxSupply;
    }

    // function setPromoNftAddress(address _promoNft) public onlyOwner {
    //     promoNft = _promoNft;
    // }
    //
    // function getPromoNftAddress() public view returns (address) {
    //     return promoNft;
    // }

    // function setPromoNftSender(address _promoNftSender) public onlyOwner {
    //     promoNftSender = _promoNftSender;
    // }
    //
    // function getPromoNftSender() public view returns (address) {
    //     return promoNftSender;
    // }

    receive() external payable {}

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(_msgSender() == owner, "Only Owner is allowed");
        _;
    }
}