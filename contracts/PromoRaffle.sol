// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@opengsn/contracts/src/ERC2771Recipient.sol";
import "./RaffleNFT.sol";

error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__ManyTicketsOnWallet();
error Raffle__upkeepNotNeeded(uint256 currentBalance, uint256 noPlayers, uint256 raffleState);
error Raffle__NftNotSet();
error Raffle__NftAlreadySet();
error Raffle__NotOwner();
error Raffle__OwnerZero();

contract PromoRaffle is ERC2771Recipient {
    enum RaffleState { OPEN, CALCULATING }

    RaffleState private s_raffleState;

    // store only tokenIds (owners can be read via ownerOf on demand)
    uint256[] private tokensInRaffle;

    uint256 public playersNeeded;
    address private s_recentWinner;
    uint256 private s_lastTimestamp;
    uint256 private s_cycles;
    address public owner;

    address public promoNft;        // set-once
    address public promoNftSender;  // set-once (kept for your flow / deployer bookkeeping)

    event RaffleEnter(address indexed _player, string _ip, bytes3 _country3, uint256 _lastTimestamp);
    event WinnerPicked(uint256 cycle, address indexed winner);
    event RaffleFundsReceived(address indexed from, uint256 amount);
    event RafflePrizePaid(address indexed winner, uint256 amount);

    constructor(uint256 _playersNeeded, address _forwarder, address _deployer) payable {
        owner = _msgSender();
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
        playersNeeded = _playersNeeded;
        s_cycles = 1;

        _setTrustedForwarder(_forwarder);

        // keep your “promoNftSender set once” behavior
        if (_deployer != address(0)) promoNftSender = _deployer;
    }

    receive() external payable {
        emit RaffleFundsReceived(msg.sender, msg.value);
    }

    /* =========================  Public entry  ========================= */

    function enterRaffle(string calldata _ip, bytes3 _country3) external {
        if (s_raffleState != RaffleState.OPEN) revert Raffle__NotOpen();
        address nft = promoNft;
        if (nft == address(0)) revert Raffle__NftNotSet();

        address sender = _msgSender();

        // one ticket per wallet
        if (RaffleNFT(nft).balanceOf(sender) > 0) revert Raffle__ManyTicketsOnWallet();

        (, uint256 mintedTokenId) = RaffleNFT(nft).mintNFTs(sender);
        tokensInRaffle.push(mintedTokenId);

        emit RaffleEnter(sender, _ip, _country3, s_lastTimestamp);

        if (tokensInRaffle.length >= playersNeeded) {
            _runRaffle();
        }
    }

    function runRaffle() external onlyOwner {
        _runRaffle();
    }

    function checkSet() public view returns (bool upkeepNeeded) {
        upkeepNeeded =
            (s_raffleState == RaffleState.OPEN) &&
            (promoNft != address(0)) &&
            (tokensInRaffle.length >= playersNeeded) &&
            (address(this).balance > 0);
    }

    /* =========================  Internal draw  ========================= */

    function _runRaffle() internal {
        if (!checkSet()) {
            revert Raffle__upkeepNotNeeded(address(this).balance, tokensInRaffle.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 len = tokensInRaffle.length;

        // pseudo-random winner index (same approach as before)
        uint256 indexOfWinner =
            uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, blockhash(block.number - 1))))
                % len;

        // derive winner from winning tokenId
        uint256 winTokenId = tokensInRaffle[indexOfWinner];
        address winner = RaffleNFT(promoNft).ownerOf(winTokenId);

        s_recentWinner = winner;
        emit WinnerPicked(s_cycles, winner);

        unchecked { ++s_cycles; }
        s_lastTimestamp = block.timestamp;

        uint256 amount = address(this).balance;
        (bool success, ) = payable(winner).call{value: amount}("");
        if (!success) revert Raffle__TransferFailed();
        emit RafflePrizePaid(winner, amount);

        // burn exactly minted tickets (no scan, no owner-only nft function)
        RaffleNFT(promoNft).burnBatch(tokensInRaffle);

        // reset for next cycle
        delete tokensInRaffle;
        s_raffleState = RaffleState.OPEN;
    }

    /* =========================  Admin / set-once  ========================= */

    function updatePlayersNeeded(uint256 _playersNeeded) external onlyOwner {
        playersNeeded = _playersNeeded;
    }

    function setPromoNftAddress(address _promoNft) external onlyOwner {
        if (_promoNft == address(0)) revert Raffle__NftNotSet();
        if (promoNft != address(0)) revert Raffle__NftAlreadySet();
        promoNft = _promoNft;
    }

    function setPromoNftSender(address _promoNftSender) external onlyOwner {
        if (_promoNftSender != address(0) && promoNftSender == address(0)) {
            promoNftSender = _promoNftSender;
        }
    }

    function updateOwner(address _owner) external onlyOwner {
        if (_owner == address(0)) revert Raffle__OwnerZero();
        owner = _owner;
    }

    /* =========================  Views (kept “часть getters”)  ========================= */

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTokensIds() external view returns (uint256[] memory) {
        return tokensInRaffle;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumberOfPlayersEntered() external view returns (uint256) {
        return tokensInRaffle.length;
    }

    function getLatestTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return playersNeeded;
    }

    function getPromoNftAddress() external view returns (address) {
        return promoNft;
    }

    function getPromoNftSender() external view returns (address) {
        return promoNftSender;
    }

    /* =========================  Modifier  ========================= */

    modifier onlyOwner() {
        if (_msgSender() != owner) revert Raffle__NotOwner();
        _;
    }
}