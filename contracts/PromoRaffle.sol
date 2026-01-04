// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@opengsn/contracts/src/ERC2771Recipient.sol";
import "./RaffleNFT.sol";

error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__ManyTicketsOnWallet();
error Raffle__upkeepNotNeeded(uint256 currentBalance, uint256 noPlayers, uint256 RaffleState);
error Raffle__NftNotSet();
error Raffle__NftAlreadySet();

contract PromoRaffle is ERC2771Recipient {
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    RaffleState private s_raffleState;

    address payable[] private s_players;
    uint256[] private tokensInRaffle;

    uint256 public playersNeeded;
    address private s_recentWinner;
    uint256 private s_lastTimestamp;
    uint256 private s_cycles;
    address public owner;

    address public promoNft = address(0);
    address public promoNftSender = address(0);

    // UPDATED: added cycle
    event RaffleEnter(address indexed _player, bytes32 _ipHash, bytes3 _country3, uint256 _lastTimestamp, uint256 cycle);

    // cheaper: no players array in event
    event WinnerPicked(uint256 cycle, uint256 playersBeforePick, address indexed winner);

    event RaffleFundsReceived(address indexed from, uint256 amount);
    event RafflePrizePaid(address indexed winner, uint256 amount);

    constructor(uint256 _playersNeeded, address _forwarder, address _deployer) payable {
        owner = _msgSender();
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
        playersNeeded = _playersNeeded;
        s_cycles++;

        _setTrustedForwarder(_forwarder);
        setPromoNftSender(_deployer);
    }

    receive() external payable {
        emit RaffleFundsReceived(msg.sender, msg.value);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function enterRaffle(bytes32 ipHash, bytes3 country3) public {
        if (s_raffleState != RaffleState.OPEN) revert Raffle__NotOpen();
        if (promoNft == address(0)) revert Raffle__NftNotSet();

        // 1 ticket per wallet (restored)
        address sender = _msgSender();
        uint256 tokenCount = RaffleNFT(promoNft).balanceOf(sender);
        if (tokenCount > 0) revert Raffle__ManyTicketsOnWallet();

        (bool transferred, uint256 mintedTokenId) = RaffleNFT(promoNft).mintNFTs(sender);
        if (!transferred) revert Raffle__TransferFailed();

        tokensInRaffle.push(mintedTokenId);

        emit RaffleEnter(sender, ipHash, country3, s_lastTimestamp, s_cycles);

        if (tokensInRaffle.length >= playersNeeded) {
            _runRaffle();
        }
    }

    function checkSet() public view returns (bool upkeepNeeded) {
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        bool hasPlayers = (tokensInRaffle.length >= playersNeeded);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && hasPlayers && hasBalance);
    }

    function runRaffle() external onlyOwner {
        _runRaffle();
    }

    function _runRaffle() internal {
        bool upkeepNeeded = checkSet();
        if (!upkeepNeeded) {
            revert Raffle__upkeepNotNeeded(address(this).balance, tokensInRaffle.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;
        uint256 playersBeforePick = s_players.length;

        // rebuild players from current tokenIds (bounded by playersNeeded)
        while (s_players.length > 0) s_players.pop();
        for (uint256 i = 0; i < tokensInRaffle.length; i++) {
            s_players.push(payable(RaffleNFT(promoNft).ownerOf(tokensInRaffle[i])));
        }

        uint256 indexOfWinner =
            uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, blockhash(block.number - 1))))
                % s_players.length;

        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        emit WinnerPicked(s_cycles, playersBeforePick, recentWinner);

        s_cycles++;
        s_lastTimestamp = block.timestamp;

        uint256 bal = address(this).balance;
        (bool success, ) = recentWinner.call{value: bal}("");
        if (!success) revert Raffle__TransferFailed();
        emit RafflePrizePaid(recentWinner, bal);

        // burn exactly minted tokenIds
        RaffleNFT(promoNft).burnBatch(tokensInRaffle);

        // clear arrays
        while (tokensInRaffle.length > 0) tokensInRaffle.pop();
        while (s_players.length > 0) s_players.pop();

        s_raffleState = RaffleState.OPEN;
    }

    function getTokensIds() public view returns (uint256[] memory) {
        return tokensInRaffle;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumberOfPlayersEntered() public view returns (uint256) {
        return tokensInRaffle.length;
    }

    function getLatestTimestamp() public view returns (uint256) {
        return s_lastTimestamp;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return playersNeeded;
    }

    function updatePlayersNeeded(uint256 _playersNeeded) public onlyOwner {
        playersNeeded = _playersNeeded;
    }

    // only-once promoNft setter
    function setPromoNftAddress(address _promoNft) public onlyOwner {
        if (_promoNft == address(0)) revert Raffle__NftNotSet();
        if (promoNft != address(0)) revert Raffle__NftAlreadySet();
        promoNft = _promoNft;
    }

    function getPromoNftAddress() public view returns (address) {
        return promoNft;
    }

    // only-once promoNftSender setter (kept)
    function setPromoNftSender(address _promoNftSender) public onlyOwner {
        if (_promoNftSender != address(0) && promoNftSender == address(0)) {
            promoNftSender = _promoNftSender;
        }
    }

    function getPromoNftSender() public view returns (address) {
        return promoNftSender;
    }

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    modifier onlyOwner() {
        if (_msgSender() != owner) revert Raffle__TransferFailed(); // minimal bytecode: reuse error
        _;
    }
}