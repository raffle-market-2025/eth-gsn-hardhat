// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
interface IConsumer { function rawFulfillRandomWords(uint256, uint256[] calldata) external; }
contract MockCoordinator {
    uint256 public requestCount;
    mapping(uint256 => address) public consumers;
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns(uint256 id) {
        id = ++requestCount; consumers[id] = msg.sender;
    }
    function fulfill(uint256 id, uint256 word) external {
        uint256[] memory words = new uint256[](1); words[0] = word;
        IConsumer(consumers[id]).rawFulfillRandomWords(id, words);
    }
    function deliver(address consumer, uint256 id, uint256 word) external {
        uint256[] memory words = new uint256[](1); words[0] = word;
        IConsumer(consumer).rawFulfillRandomWords(id, words);
    }
}
contract MockMarketplace {
    uint256 public next = 1;
    mapping(uint256 => address) public raffles;
    function add(address raffle) external { raffles[next++] = raffle; }
    function getNextTickerId() external view returns(uint256) { return next; }
    function getRaffleAddress(uint256 id) external view returns(address) { return raffles[id]; }
    function invoke(address target, bytes calldata data) external payable {
        (bool ok, bytes memory result) = target.call{value:msg.value}(data);
        if (!ok) assembly { revert(add(result,32), mload(result)) }
    }
    fallback() external {}
}
contract MockRaffle {
    bool public ready;
    bool public calculating;
    bool public fail;
    uint256 public result;
    uint256 public remaining;
    uint256 public state;
    function configure(bool r, bool f, uint256 st, uint256 rem) external { ready=r; fail=f; state=st; remaining=rem; }
    function isReadyToDraw() external view returns(bool) { return ready && !calculating; }
    function startDraw() external { require(ready && !calculating); calculating=true; }
    function finalizeFromRandomWords(uint256[] calldata words) external {
        require(calculating && !fail); result=words[0]; calculating=false; ready=false;
    }
    function getCurrentState() external view returns(uint256) { return state; }
    function cleanupRemaining() external view returns(uint256) { return remaining; }
    function cleanupBurn(uint256 count) external { remaining = count >= remaining ? 0 : remaining-count; }
}
contract MockLink {
    mapping(address => uint256) public balanceOf;
    address public lastRegistrar;
    bytes public lastData;
    function mint(address to, uint256 amount) external { balanceOf[to]+=amount; }
    function transferAndCall(address to,uint256 amount,bytes calldata data) external returns(bool) {
        require(balanceOf[msg.sender]>=amount); balanceOf[msg.sender]-=amount; balanceOf[to]+=amount;
        lastRegistrar=to; lastData=data; return true;
    }
}
contract RejectingPlayer {
    receive() external payable { revert("Rejected"); }
    function invoke(address target, bytes calldata data) external payable {
        (bool ok, bytes memory result) = target.call{value:msg.value}(data);
        if (!ok) assembly { revert(add(result,32), mload(result)) }
    }
}
contract SelectiveEntrant {
    function enterAndRequireWin(address promo,bytes calldata data) external {
        (bool ok, ) = promo.call(data); require(ok,"Entry failed");
        (bool read, bytes memory value) = promo.staticcall(abi.encodeWithSignature("getRecentWinner()"));
        require(read && abi.decode(value,(address))==address(this),"Not winner");
    }
    receive() external payable {}
}
contract MockForwarder {
    function supportsInterface(bytes4 id) external pure returns(bool) { return id != 0xffffffff; }
    function forward(address target, bytes calldata data, address from) external {
        (bool ok, bytes memory value) = target.call(bytes.concat(data,bytes20(from)));
        if (!ok) assembly { revert(add(value,32),mload(value)) }
    }
}
contract MockRelayHub {
    function supportsInterface(bytes4 id) external pure returns(bool) { return id != 0xffffffff; }
    function invoke(address target,bytes calldata data) external returns(bytes memory value) {
        bool ok; (ok,value)=target.call(data);
        if (!ok) assembly { revert(add(value,32),mload(value)) }
    }
}
