// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC2771Recipient} from "@opengsn/contracts/src/ERC2771Recipient.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {RaffleNFT} from "./RaffleNFT.sol";

/// @notice Signed admission followed by an asynchronous VRF draw and pull payments.
contract PromoRaffle is ERC2771Recipient, EIP712, VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    enum RaffleState { OPEN, CALCULATING }
    struct Config {
        address coordinator;
        uint256 subscriptionId;
        bytes32 keyHash;
        uint32 callbackGasLimit;
        address entrySigner;
    }
    bytes32 public constant ENTRY_TYPEHASH = keccak256(
        "Entry(address participant,bytes32 ipHash,bytes2 country2,uint256 cycle,uint256 deadline)"
    );
    uint256 public constant MAX_PLAYERS = 200;
    Config public vrfConfig;
    address public immutable entrySigner;
    uint256 public playersNeeded;
    address public promoNft;
    address public promoNftSender;
    uint256 public pendingRequestId;
    bool public randomnessReady;
    uint256 public randomWord;
    uint256 public cyclePrize;
    uint256 public totalClaimable;
    mapping(address => uint256) public claimable;
    mapping(uint256 => mapping(bytes32 => bool)) private s_ipUsedByCycle;
    mapping(uint256 => mapping(address => bool)) public walletUsedByCycle;
    address payable[] private s_players;
    uint256[] private tokensInRaffle;
    RaffleState private s_raffleState;
    address private s_recentWinner;
    uint256 private s_lastTimestamp;
    uint256 private s_cycles = 1;

    event RaffleEnter(address indexed _player, bytes32 _ipHash, bytes2 _country2, uint256 _lastTimestamp, uint256 cycle);
    event WinnerPicked(uint256 cycle, uint256 playersBeforePick, address indexed winner);
    event RaffleFundsReceived(address indexed from, uint256 amount);
    event RafflePrizePaid(address indexed winner, uint256 amount);
    event DrawRequested(uint256 indexed cycle, uint256 indexed requestId);
    event RandomnessReceived(uint256 indexed requestId);
    event PrizeAllocated(address indexed winner, uint256 amount);

    constructor(uint256 count, address forwarder, address deployer, Config memory config)
        EIP712("PromoRaffle", "1") VRFConsumerBaseV2Plus(config.coordinator) payable
    {
        require(count > 0 && count <= MAX_PLAYERS, "Invalid players count");
        require(config.entrySigner != address(0) && config.subscriptionId > 0 && config.callbackGasLimit >= 100_000, "Invalid config");
        playersNeeded = count;
        vrfConfig = config;
        entrySigner = config.entrySigner;
        promoNftSender = deployer;
        s_lastTimestamp = block.timestamp;
        _setTrustedForwarder(forwarder);
    }

    receive() external payable { emit RaffleFundsReceived(msg.sender, msg.value); }

    /// @dev The admission service must derive the IP itself and enforce its eligibility policy.
    /// The signature cannot be replayed on another wallet, cycle, chain, or raffle.
    function enterRaffle(bytes32 ipHash, bytes2 country2, uint256 deadline, bytes calldata signature) external {
        require(s_raffleState == RaffleState.OPEN, "Raffle not open");
        require(promoNft != address(0), "NFT not set");
        address sender = _msgSender();
        require(!walletUsedByCycle[s_cycles][sender], "Wallet already entered");
        require(!s_ipUsedByCycle[s_cycles][ipHash], "IP already entered");
        require(block.timestamp <= deadline && ipHash != bytes32(0), "Invalid admission");
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(ENTRY_TYPEHASH, sender, ipHash, country2, s_cycles, deadline)));
        require(ECDSA.recover(digest, signature) == entrySigner, "Invalid signature");
        walletUsedByCycle[s_cycles][sender] = true;
        s_ipUsedByCycle[s_cycles][ipHash] = true;
        (bool minted, uint256 tokenId) = RaffleNFT(promoNft).mintNFTs(sender);
        require(minted, "Mint failed");
        tokensInRaffle.push(tokenId);
        // Eligibility belongs to the admitted wallet, independent of subsequent NFT transfers.
        s_players.push(payable(sender));
        emit RaffleEnter(sender, ipHash, country2, s_lastTimestamp, s_cycles);
        if (s_players.length == playersNeeded) _requestDraw();
    }

    function checkSet() public view returns (bool) {
        return s_raffleState == RaffleState.OPEN && s_players.length == playersNeeded && address(this).balance > totalClaimable;
    }

    function runRaffle() external onlyOwner { _requestDraw(); }

    function _requestDraw() private {
        require(checkSet(), "Draw not ready");
        s_raffleState = RaffleState.CALCULATING;
        cyclePrize = address(this).balance - totalClaimable;
        pendingRequestId = s_vrfCoordinator.requestRandomWords(VRFV2PlusClient.RandomWordsRequest({
            keyHash: vrfConfig.keyHash, subId: vrfConfig.subscriptionId, requestConfirmations: 3,
            callbackGasLimit: vrfConfig.callbackGasLimit, numWords: 1,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
        }));
        emit DrawRequested(s_cycles, pendingRequestId);
    }

    // No recipient calls or loops in the charged VRF callback.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata words) internal override {
        if (s_raffleState != RaffleState.CALCULATING || requestId != pendingRequestId || randomnessReady || words.length != 1) return;
        randomWord = words[0];
        randomnessReady = true;
        emit RandomnessReceived(requestId);
    }

    /// @notice Can be called by any keeper. Retrying cannot change the stored randomness.
    function finalizeCycle() public {
        require(s_raffleState == RaffleState.CALCULATING && randomnessReady, "Randomness unavailable");
        address winner = s_players[randomWord % s_players.length];
        s_recentWinner = winner;
        uint256 prize = cyclePrize;
        claimable[winner] += prize;
        totalClaimable += prize;
        emit WinnerPicked(s_cycles, s_players.length, winner);
        emit PrizeAllocated(winner, prize);
        RaffleNFT(promoNft).burnBatch(tokensInRaffle);
        delete tokensInRaffle;
        delete s_players;
        cyclePrize = 0;
        randomnessReady = false;
        pendingRequestId = 0;
        randomWord = 0;
        s_cycles++;
        s_lastTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory) {
        return (s_raffleState == RaffleState.CALCULATING && randomnessReady, bytes(""));
    }
    function performUpkeep(bytes calldata) external override { finalizeCycle(); }

    function claimPrize() external {
        address sender = _msgSender();
        uint256 amount = claimable[sender];
        require(amount > 0, "No prize");
        claimable[sender] = 0;
        totalClaimable -= amount;
        (bool sent, ) = payable(sender).call{value: amount}("");
        require(sent, "Prize transfer failed");
        emit RafflePrizePaid(sender, amount);
    }

    function updatePlayersNeeded(uint256 count) external onlyOwner {
        require(s_raffleState == RaffleState.OPEN && s_players.length == 0, "Cycle in progress");
        require(count > 0 && count <= MAX_PLAYERS, "Invalid players count");
        playersNeeded = count;
    }
    function setPromoNftAddress(address nft) external onlyOwner {
        require(nft.code.length > 0 && promoNft == address(0), "Invalid NFT");
        require(RaffleNFT(nft).raffleAddress() == address(this), "Wrong raffle NFT");
        promoNft = nft;
    }
    function getBalance() external view returns (uint256) { return address(this).balance; }
    function getCycle() external view returns (uint256) { return s_cycles; }
    function getTokensIds() external view returns (uint256[] memory) { return tokensInRaffle; }
    function getRecentWinner() external view returns (address) { return s_recentWinner; }
    function getRaffleState() external view returns (RaffleState) { return s_raffleState; }
    function getNumberOfPlayersEntered() external view returns (uint256) { return s_players.length; }
    function getLatestTimestamp() external view returns (uint256) { return s_lastTimestamp; }
    function getNumberOfPlayers() external view returns (uint256) { return playersNeeded; }
    function getPromoNftAddress() external view returns (address) { return promoNft; }
    function getPromoNftSender() external view returns (address) { return promoNftSender; }
    function isIpUsed(bytes32 ipHash) external view returns (bool) { return s_ipUsedByCycle[s_cycles][ipHash]; }
    function isIpUsedInCycle(uint256 cycle, bytes32 ipHash) external view returns (bool) { return s_ipUsedByCycle[cycle][ipHash]; }
}
