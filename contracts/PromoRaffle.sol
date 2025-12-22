// What we need to do
/* Users can enter the lottery
   We pick a random winner from the entered players
   @todo Winner to be selected within X minutes -> should be completely automated
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@opengsn/contracts/src/ERC2771Recipient.sol";
import "./RaffleNFT.sol";

error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__ManyTicketsOnWallet();
error Raffle__upkeepNotNeeded(uint256 currentBalance, uint256 noPlayers, uint256 RaffleState);

/** @title A PromoRaffle Contract
    @author 2024-Aman, 2025-Tarasenko
    @notice This contact is for creating an untamperable decentralized lottery 
    @dev this contract implements GSN
 */
contract PromoRaffle is ERC2771Recipient {
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    RaffleState private s_raffleState;

    address payable[] private s_players;
    uint[] private tokensInRaffle;

    uint public playersNeeded;
    address private s_recentWinner;
    uint256 private s_lastTimestamp;
    uint256 private s_cycles;
    address public owner;

    address promoNft = address(0);
    address promoNftSender = address(0);

    
    event RaffleEnter( address indexed _player, string _ip, bytes3 _country3, uint256 _lastTimestamp);
    event WinnerPicked( uint256 cycle, address payable[] players, address indexed winner);
    event RaffleFundsReceived( address indexed from, uint256 amount);
    event RafflePrizePaid( address indexed winner, uint256 amount);


    constructor(
        uint _playersNeeded,
        address _forwarder,
        address _deployer
    ) payable {
        owner = _msgSender();
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
        playersNeeded = _playersNeeded;
        s_cycles ++;

        _setTrustedForwarder(_forwarder);
        setPromoNftSender(_deployer);
    }

    receive() external payable {
        emit RaffleFundsReceived(msg.sender, msg.value);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function enterRaffle(string calldata _ip, bytes3 _country3) public  {       
        if (s_raffleState != RaffleState.OPEN) { revert Raffle__NotOpen(); }

        uint tokenCount = RaffleNFT(promoNft).balanceOf(_msgSender());
        if(tokenCount > 0) { revert Raffle__ManyTicketsOnWallet(); }

        (bool transferred, uint mintedTokenId) = RaffleNFT(promoNft).mintNFTs(_msgSender());        
        require(transferred, "Can't transfer");

        //s_players.push(payable(_msgSender()));
        tokensInRaffle.push(mintedTokenId);

        // Whenever we update a dynamic object like array or mapping, we should emit events
        emit RaffleEnter(_msgSender(), _ip, _country3, s_lastTimestamp);

        if (tokensInRaffle.length >= playersNeeded) {
            _runRaffle();
        }
    }

    function checkSet() public view returns (bool upkeepNeeded)
    {
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        bool hasPlayers = (tokensInRaffle.length >= playersNeeded);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && hasPlayers && hasBalance);
    }

    // External func are cheaper this func is automatically called by chainlink no
    function runRaffle() external onlyOwner {
        _runRaffle();
    }

    function _runRaffle() internal {
        bool upkeepNeeded = checkSet();
        if (!upkeepNeeded) {
            revert Raffle__upkeepNotNeeded(address(this).balance, tokensInRaffle.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        for(uint i = 0; i < tokensInRaffle.length; i++) {            
            s_players.push( payable(RaffleNFT(promoNft).ownerOf(tokensInRaffle[i])));
        }

        // Generate pseudo-random number using blockhash and timestamp, in range [0, s_players.length]
        uint256 indexOfWinner = uint256(
                keccak256(abi.encodePacked(block.prevrandao, block.timestamp, blockhash(block.number - 1)))
            ) % s_players.length;

        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        emit WinnerPicked(s_cycles, s_players, recentWinner);

        s_cycles ++;
        s_lastTimestamp = block.timestamp;

        // transfer raffle balance onto recentWinner
        uint256 _balance = address(this).balance;
        (bool success, ) = recentWinner.call{value: _balance}("");
        if (!success) { revert Raffle__TransferFailed(); }
        emit RafflePrizePaid(recentWinner, _balance);

        s_raffleState = RaffleState.OPEN;

        for (uint i = 0; i < s_players.length; i++) {
           RaffleNFT(promoNft).burn(s_players[i]);  
        }
        while(s_players.length > 0) {
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

    function getNumberOfPlayersEntered() public view returns (uint256) {
        return tokensInRaffle.length;
    }

    function getLatestTimestamp() public view returns (uint256) {
        return s_lastTimestamp;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return playersNeeded;
    }

    function updatePlayersNeeded(uint _playersNeeded) public onlyOwner {
        playersNeeded = _playersNeeded;
    }

    // only-once promoNft setter
    function setPromoNftAddress(address _promoNft) public onlyOwner {
        if (_promoNft != address(0) && promoNft == address(0)) {
            promoNft = _promoNft;
        }   
    }

    function getPromoNftAddress() public view returns (address) {
        return promoNft;
    }

    // only-once promoNftSender setter
    function setPromoNftSender(address _promoNftSender) public onlyOwner {
        if (_promoNftSender != address(0) && promoNftSender == address(0)) {
            promoNftSender = _promoNftSender;
        }
    }

    function getPromoNftSender() public view returns (address) {
        return promoNftSender;
    }

    function updateOwner(address _owner) external onlyOwner{
        owner = _owner;
    }

    modifier onlyOwner() {
        require(_msgSender()==owner,"Only Owner is allowed");
        _;
    }
}