const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const solc = require('solc');
const { ethers } = require('ethers');
const ganache = require('ganache');
const root = path.resolve(__dirname, '..');
let compiled;
before(() => {
  const sources = {};
  // Resolve relative to each importer, matching Hardhat/npm's nested dependency graph.
  function gather(absolute) {
    const key = path.relative(root, absolute).split(path.sep).join('/');
    if (sources[key]) return key;
    sources[key] = { content: '' };
    const content = fs.readFileSync(absolute, 'utf8').replace(/\bimport\s+[^;]+;/g, statement => {
      return statement.replace(/["']([^"']+)["']/, (_, specifier) => {
        const dependency = specifier.startsWith('.')
          ? path.resolve(path.dirname(absolute), specifier)
          : require.resolve(specifier, { paths: [path.dirname(absolute)] });
        return JSON.stringify(gather(dependency));
      });
    });
    sources[key].content = content;
    return key;
  }
  for (const name of fs.readdirSync(path.join(root, 'contracts')).filter(n => n.endsWith('.sol'))) {
    gather(path.join(root, 'contracts', name));
  }
  gather(path.join(__dirname, 'fixtures/SecurityMocks.sol'));
  const output = JSON.parse(solc.compile(JSON.stringify({ language: 'Solidity', sources, settings: {
    optimizer: { enabled: true, runs: 200 }, viaIR: true, evmVersion: 'shanghai',
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object'] } }
  }})));
  const errors = (output.errors || []).filter(e => e.severity === 'error');
  assert.equal(errors.length, 0, errors.map(e => e.formattedMessage).join('\n'));
  compiled = output.contracts;
});
function artifact(name) {
  for (const file of Object.values(compiled)) if (file[name]) return file[name];
  throw new Error(`Missing ${name}`);
}
async function environment() {
  const rpc = ganache.provider({ logging: { quiet: true }, chain: { hardfork: 'shanghai' }, wallet: { totalAccounts: 8 } });
  const provider = new ethers.BrowserProvider(rpc, undefined, { cacheTimeout: -1 });
  provider.pollingInterval = 10;
  const signers = await Promise.all([0,1,2,3,4,5].map(i => provider.getSigner(i)));
  const addresses = await Promise.all(signers.map(s => s.getAddress()));
  const deploy = async (name, args = [], value = 0n) => {
    const a = artifact(name);
    const contract = await new ethers.ContractFactory(a.abi, a.evm.bytecode.object, signers[0]).deploy(...args, { value });
    await contract.waitForDeployment(); return contract;
  };
  return { rpc, provider, signers, addresses, deploy };
}
const send = async tx => (await tx).wait();
const rejected = async fn => assert.rejects(fn);
async function automation(e, maxScan = 2, maxBatch = 2) {
  const market = await e.deploy('MockMarketplace');
  const coordinator = await e.deploy('MockCoordinator');
  const link = await e.deploy('MockLink');
  const auto = await e.deploy('RaffleAutomationVRF', [market.target, coordinator.target, 1, ethers.ZeroHash, 150000, link.target, e.addresses[4], maxBatch, maxScan]);
  const cleanup = await e.deploy('RaffleCleanupAutomation', [market.target, link.target, e.addresses[4], maxBatch, maxScan, 2]);
  return { market, coordinator, link, auto, cleanup };
}
async function paidRaffle(e, options = {}) {
  const market = await e.deploy('MockMarketplace');
  const raffle = await e.deploy('RaffleContract');
  await send(raffle.initialize(1, 100, options.threshold ?? 50, e.addresses[1], e.addresses[0], [['Prize','0x5553',10]], [[0,10,100,0]], market.target));
  const nft = await e.deploy('RaffleNFT');
  await send(nft.initialize(raffle.target, ''));
  await send(market.invoke(raffle.target, raffle.interface.encodeFunctionData('setRaffleNFT',[nft.target])));
  return { raffle, nft, market };
}
async function promoRaffle(e, count = 2, forwarder = ethers.ZeroAddress) {
  const coordinator = await e.deploy('MockCoordinator');
  const authority = ethers.Wallet.createRandom();
  const promo = await e.deploy('PromoRaffle', [count, forwarder, e.addresses[0], [coordinator.target,1,ethers.ZeroHash,150000,authority.address]], 1000n);
  const nft = await e.deploy('RaffleNFT');
  await send(nft.initialize(promo.target, ''));
  await send(promo.setPromoNftAddress(nft.target));
  const domain = { name:'PromoRaffle', version:'1', chainId:(await e.provider.getNetwork()).chainId, verifyingContract:promo.target };
  const types = { Entry:[{name:'participant',type:'address'},{name:'ipHash',type:'bytes32'},{name:'country2',type:'bytes2'},{name:'cycle',type:'uint256'},{name:'deadline',type:'uint256'}] };
  const admission = async (participant = e.addresses[1], overrides = {}, signer = authority, domainOverride = {}) => {
    const value = { participant, ipHash:ethers.id(participant), country2:'0x5541', cycle:await promo.getCycle(), deadline:BigInt((await e.provider.getBlock('latest')).timestamp+3600), ...overrides };
    const signature = await signer.signTypedData({...domain,...domainOverride}, types, value);
    return { value, args:[value.ipHash,value.country2,value.deadline,signature] };
  };
  return { promo, nft, coordinator, authority, admission };
}

test('C-01: credentials are local-only and offline networks do not fork', () => {
  // Local ignored credentials are valid; committed credentials are not.
  let tracked = [];
  try { tracked = execFileSync('git',['ls-files','-z'],{cwd:root,encoding:'utf8'}).split('\0'); } catch {}
  for (const file of ['.env','mnemonic.txt','config/gsn-relay-config.json']) {
    assert.equal(tracked.includes(file) && fs.existsSync(path.join(root,file)),false, `Tracked credential: ${file}`);
  }
  const config = fs.readFileSync(path.join(root,'hardhat.config.ts'),'utf8');
  assert.match(config,/configVariable\("SEPOLIA_PRIVATE_KEY"\)/);
  assert.doesNotMatch(config,/accounts:\s*\[\s*["'][a-fA-F0-9]{64}["']/);
  assert.doesNotMatch(config,/infura\.io\/v3\/[a-fA-F0-9]{32}|apiKey:\s*["'][A-Za-z0-9]{20,}/);
  assert.doesNotMatch(config,/forking:/);
  const ignores = fs.readFileSync(path.join(root,'.gitignore'),'utf8');
  for (const rule of ['.env','mnemonic.txt','config/gsn-relay-config.json']) assert.ok(ignores.split('\n').includes(rule));
});

test('all production contracts compile and fit the EIP-170 deployment limit', () => {
  for (const [file, contracts] of Object.entries(compiled)) {
    if (!file.startsWith('contracts/')) continue;
    for (const [name, a] of Object.entries(contracts)) assert.ok(a.evm.deployedBytecode.object.length/2<=24576, `${name} exceeds EIP-170`);
  }
});

test('H-01: real raffle receives authenticated VRF and finalizes through Automation', async t => {
  const e = await environment(); t.after(()=>e.rpc.disconnect());
  const {market,coordinator,link,auto} = await automation(e);
  const raffle = await e.deploy('RaffleContract');
  await send(raffle.initialize(1,10,0,e.addresses[1],e.addresses[0],[['Prize','0x5553',10]],[[0,10,100,0]],market.target));
  const nft = await e.deploy('RaffleNFT'); await send(nft.initialize(raffle.target,''));
  await send(market.invoke(raffle.target,raffle.interface.encodeFunctionData('setRaffleNFT',[nft.target])));
  await send(market.invoke(raffle.target,raffle.interface.encodeFunctionData('setAutomation',[auto.target])));
  await send(market.add(raffle.target)); await send(raffle.connect(e.signers[1]).enterRaffle({value:100}));
  await e.provider.send('evm_increaseTime',[20]); await e.provider.send('evm_mine',[]);
  await send(auto.performUpkeep('0x', { gasLimit: 2_000_000 }));
  assert.equal(await raffle.getCurrentState(),2n);
  await rejected(()=>auto.connect(e.signers[2]).rawFulfillRandomWords.staticCall(1,[42]));
  await send(coordinator.fulfill(1,42));
  assert.equal(await auto.requestFulfilled(1),true);
  assert.equal(await raffle.getCurrentState(),2n);
  await send(auto.connect(e.signers[2]).performUpkeep('0x', { gasLimit: 2_000_000 }));
  assert.equal(await raffle.getCurrentState(),3n);
  assert.deepEqual(Array.from(await raffle.getRecentWinners()),[e.addresses[1]]);
  assert.equal(await auto.inFlight(1),false);
});

test('H-01: failed finalization retries the same stored random word, including zero', async t => {
  const e = await environment(); t.after(()=>e.rpc.disconnect());
  const {market,coordinator,auto} = await automation(e);
  const raffle = await e.deploy('MockRaffle'); await send(raffle.configure(true,true,0,0)); await send(market.add(raffle.target));
  await send(auto.performUpkeep('0x', { gasLimit: 2_000_000 })); await send(coordinator.fulfill(1,0));
  await rejected(()=>auto.finalizeRaffle.staticCall(1,1));
  assert.equal(await auto.inFlight(1),true); assert.equal(await auto.requestFulfilled(1),true);
  await send(coordinator.deliver(auto.target,1,999)); assert.equal(await auto.requestRandomWord(1),0n);
  await send(raffle.configure(true,false,0,0));
  await send(auto.connect(e.signers[2]).finalizeRaffle(1,1));
  const expected=BigInt(ethers.solidityPackedKeccak256(['uint256','uint256','uint256','address'],[0,1,1,raffle.target]));
  assert.equal(await raffle.result(),expected); assert.equal(await coordinator.requestCount(),1n);
  assert.equal(await auto.pendingRaffles(),0n);
  await rejected(()=>auto.finalizeRaffle.staticCall(1,1));
});

test('H-02: host and marketplace owner can each cancel; outsider can only cancel an expired failure', async t => {
  const e = await environment(); t.after(()=>e.rpc.disconnect());
  for (const index of [0,1]) {
    const {raffle} = await paidRaffle(e); await send(raffle.connect(e.signers[index]).revertLottery());
    assert.equal(await raffle.getCurrentState(),4n);
  }
  const {raffle} = await paidRaffle(e);
  await rejected(()=>raffle.connect(e.signers[2]).revertLottery.staticCall());
  await e.provider.send('evm_increaseTime',[101]); await e.provider.send('evm_mine',[]);
  await send(raffle.connect(e.signers[2]).revertLottery()); assert.equal(await raffle.getCurrentState(),4n);
});

test('H-02: pull refunds survive cleanup and a rejecting recipient does not block other owners', async t => {
  const e = await environment(); t.after(()=>e.rpc.disconnect());
  const {raffle,nft} = await paidRaffle(e);
  const rejector = await e.deploy('RejectingPlayer');
  await send(rejector.invoke(raffle.target,raffle.interface.encodeFunctionData('enterRaffle'),{value:100}));
  await send(raffle.connect(e.signers[2]).enterRaffle({value:100}));
  await send(raffle.connect(e.signers[1]).revertLottery());
  assert.equal(await raffle.cleanupRemaining(),0n);
  await rejected(()=>raffle.cleanupBurn.staticCall(2));
  await rejected(()=>rejector.invoke.staticCall(raffle.target,raffle.interface.encodeFunctionData('claimRefund',[1])));
  assert.equal(await nft.ownerOf(1),rejector.target);
  await send(raffle.connect(e.signers[2]).claimRefund(2)); assert.equal(await raffle.refundClaimed(2),true);
  assert.equal(await raffle.getBalance(),100n);
  await rejected(()=>raffle.connect(e.signers[2]).claimRefund.staticCall(2));
  await rejected(()=>raffle.connect(e.signers[0])._sendFundsToMarketplace.staticCall());
});

test('H-03: both automation contracts reject direct registration and unauthorized wrappers; owner can register', async t => {
  const e = await environment(); t.after(()=>e.rpc.disconnect());
  const {auto,cleanup,link} = await automation(e);
  const abi = new ethers.Interface(['function registerAndPredictID(string,bytes,address,uint32,address,bytes,uint96,uint8)']);
  for (const c of [auto,cleanup]) {
    await send(link.mint(c.target,100));
    const data = abi.encodeFunctionData('registerAndPredictID',['attack','0x',e.addresses[2],500000,e.addresses[2],'0x',100,0]);
    await rejected(()=>e.signers[2].call({to:c.target,data}));
    await rejected(()=>c.connect(e.signers[2]).registerThisUpkeep.staticCall('attack',500000,100,0));
    assert.equal(await link.balanceOf(c.target),100n);
    await send(c.registerThisUpkeep('legitimate',500000,10,0)); assert.equal(await link.balanceOf(c.target),90n);
  }
});

test('H-04: empty windows advance both cursors and reach a ready raffle beyond MAX_SCAN', async t => {
  const e = await environment(); t.after(()=>e.rpc.disconnect());
  const {market,coordinator,auto,cleanup} = await automation(e,2,1);
  for (let i=0;i<3;i++) { const r=await e.deploy('MockRaffle'); await send(r.configure(i===2,false,i===2?3:0,i===2?3:0)); await send(market.add(r.target)); }
  for (const c of [auto,cleanup]) {
    const [needed] = await c.checkUpkeep('0x'); assert.equal(needed,true);
    await send(c.performUpkeep('0x', { gasLimit: 2_000_000 })); assert.equal(await c.scanCursor(),3n);
    assert.equal((await c.checkUpkeep('0x'))[0],true);
    await send(c.performUpkeep('0x', { gasLimit: 2_000_000 })); assert.equal(await c.scanCursor(),1n);
  }
  assert.equal(await coordinator.requestCount(),1n);
  const third = new ethers.Contract(await market.getRaffleAddress(3),artifact('MockRaffle').abi,e.signers[0]);
  assert.equal(await third.remaining(),1n);
});

test('H-04: a fully scanned idle registry does not request unnecessary upkeep', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());
  const {market,auto,cleanup}=await automation(e);
  const r=await e.deploy('MockRaffle'); await send(market.add(r.target));
  for(const c of [auto,cleanup]){assert.equal((await c.checkUpkeep('0x'))[0],false);await rejected(()=>c.performUpkeep.staticCall('0x'));}
});

test('batch limits and cursor cannot be bypassed with forged performData', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());
  const {market,auto,cleanup}=await automation(e,2,1);
  for(let i=0;i<4;i++){const r=await e.deploy('MockRaffle');await send(r.configure(true,false,3,5));await send(market.add(r.target));}
  const forged=ethers.AbiCoder.defaultAbiCoder().encode(['uint256[]','uint256'],[[1,2,3,4],4]);
  await send(auto.performUpkeep(forged, { gasLimit: 2_000_000 }));assert.equal((await auto.getRequestBatch(1)).length,1);assert.equal(await auto.scanCursor(),2n);
  await send(cleanup.performUpkeep(forged, { gasLimit: 2_000_000 }));assert.equal(await cleanup.scanCursor(),2n);
});

test('H-05: transferred NFT does not allow a second entry by the same wallet', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect()); const {promo,nft,admission}=await promoRaffle(e,3);
  const first=await admission();await send(promo.connect(e.signers[1]).enterRaffle(...first.args));
  await send(nft.connect(e.signers[1]).transferFrom(e.addresses[1],e.addresses[2],1));
  const second=await admission(e.addresses[1],{ipHash:ethers.id('another-ip')});
  await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(...second.args));
  assert.equal(await promo.getNumberOfPlayersEntered(),1n);
});

test('H-05: entry signatures bind IP, country, wallet, deadline, chain, contract and cycle', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const {promo,admission,coordinator}=await promoRaffle(e,1);
  const valid=await admission();
  await rejected(()=>promo.connect(e.signers[2]).enterRaffle.staticCall(...valid.args));
  await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(ethers.id('forged'),...valid.args.slice(1)));
  await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(valid.args[0],'0x5553',...valid.args.slice(2)));
  for(const changes of [{deadline:1},{cycle:2}]){const a=await admission(e.addresses[1],changes);await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(...a.args));}
  for(const domain of [{chainId:1},{verifyingContract:e.addresses[4]}]){const a=await admission(e.addresses[1],{},undefined,domain);await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(...a.args));}
  const bad=await admission(e.addresses[1],{},ethers.Wallet.createRandom());await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(...bad.args));
  await send(promo.connect(e.signers[1]).enterRaffle(...valid.args));await send(coordinator.fulfill(1,42));await send(promo.finalizeCycle());
  await rejected(()=>promo.connect(e.signers[1]).enterRaffle.staticCall(...valid.args));
});

test('H-05: a server-attested IP cannot be reused by a different wallet', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const {promo,admission}=await promoRaffle(e,3);
  const a=await admission();await send(promo.connect(e.signers[1]).enterRaffle(...a.args));
  const b=await admission(e.addresses[2],{ipHash:a.value.ipHash});await rejected(()=>promo.connect(e.signers[2]).enterRaffle.staticCall(...b.args));
});

test('H-05: valid GSN forwarded entry uses the signed participant, not the forwarder', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const forwarder=await e.deploy('MockForwarder');
  const {promo,admission}=await promoRaffle(e,2,forwarder.target);const a=await admission();
  await send(forwarder.forward(promo.target,promo.interface.encodeFunctionData('enterRaffle',a.args),e.addresses[1]));
  assert.equal(await promo.walletUsedByCycle(1,e.addresses[1]),true);
  assert.equal(await promo.walletUsedByCycle(1,forwarder.target),false);
});

test('H-06: last entry cannot observe/select a winner; VRF freezes admission and ownership', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const {promo,nft,admission,coordinator}=await promoRaffle(e,2);
  const first=await admission();await send(promo.connect(e.signers[1]).enterRaffle(...first.args));
  const attacker=await e.deploy('SelectiveEntrant');const a=await admission(attacker.target);
  await rejected(()=>attacker.enterAndRequireWin.staticCall(promo.target,promo.interface.encodeFunctionData('enterRaffle',a.args)));
  assert.equal(await promo.getRaffleState(),0n);assert.equal(await coordinator.requestCount(),0n);
  const second=await admission(e.addresses[2]);await send(promo.connect(e.signers[2]).enterRaffle(...second.args));
  assert.equal(await promo.getRaffleState(),1n);assert.equal(await promo.getRecentWinner(),ethers.ZeroAddress);
  await rejected(()=>promo.finalizeCycle.staticCall());
  await rejected(()=>promo.connect(e.signers[3]).rawFulfillRandomWords.staticCall(1,[1]));
  await rejected(()=>promo.updatePlayersNeeded.staticCall(1));
  const late=await admission(e.addresses[3]);await rejected(()=>promo.connect(e.signers[3]).enterRaffle.staticCall(...late.args));
  await send(nft.connect(e.signers[1]).transferFrom(e.addresses[1],e.addresses[3],1));
  await send(coordinator.fulfill(1,0));await send(coordinator.deliver(promo.target,1,1));
  assert.equal(await promo.randomWord(),0n);
  assert.equal((await promo.checkUpkeep('0x'))[0],true);
  await send(promo.connect(e.signers[3]).performUpkeep('0x', { gasLimit: 2_000_000 }));assert.equal(await promo.getRecentWinner(),e.addresses[1]);
  assert.equal(await promo.claimable(e.addresses[1]),1000n);assert.equal(await promo.getCycle(),2n);
  await send(promo.connect(e.signers[1]).claimPrize());assert.equal(await promo.totalClaimable(),0n);
  await rejected(()=>promo.connect(e.signers[1]).claimPrize.staticCall());
});

test('H-06: rejecting winner cannot block finalization or spend previously reserved prizes', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const {promo,admission,coordinator}=await promoRaffle(e,1);
  const rejector=await e.deploy('RejectingPlayer');const a=await admission(rejector.target);
  await send(rejector.invoke(promo.target,promo.interface.encodeFunctionData('enterRaffle',a.args)));
  await send(coordinator.fulfill(1,99));await send(promo.finalizeCycle());assert.equal(await promo.getRaffleState(),0n);
  await rejected(()=>rejector.invoke.staticCall(promo.target,promo.interface.encodeFunctionData('claimPrize')));
  assert.equal(await promo.claimable(rejector.target),1000n);
  await send(e.signers[0].sendTransaction({to:promo.target,value:500}));const b=await admission();
  await send(promo.connect(e.signers[1]).enterRaffle(...b.args));assert.equal(await promo.cyclePrize(),500n);
  await send(coordinator.fulfill(2,3));await send(promo.finalizeCycle());assert.equal(await promo.totalClaimable(),1500n);
});


test('deployment: real marketplace clones initialize and a third-party host can buy/cancel/refund', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());
  const market=await e.deploy('RaffleMarketplace');
  const implementation=await e.deploy('RaffleContract');const nftImplementation=await e.deploy('RaffleNFT');
  const verifier=await e.deploy('Verifier',[market.target,implementation.target]);
  await send(market.setVerifier(verifier.target));await send(market.setAutomation(e.addresses[5]));
  await send(market.setRaffleNftImplementation(nftImplementation.target));
  await send(market.connect(e.signers[1]).createRaffle(100,50,[['Prize','0x5553',10]],[[0,10,100,0]],'ipfs://tickets','',''));
  const record=await market.getRaffleRecord(1);
  const raffle=new ethers.Contract(record[0],artifact('RaffleContract').abi,e.signers[1]);
  const nft=new ethers.Contract(record[2],artifact('RaffleNFT').abi,e.signers[1]);
  await send(raffle.enterRaffle({value:100}));assert.equal(await nft.ownerOf(1),e.addresses[1]);
  await send(raffle.revertLottery());await send(raffle.claimRefund(1));
  assert.equal(await raffle.getBalance(),0n);assert.equal(await raffle.refundClaimed(1),true);
});

test('H-02: an unrelated caller cannot cancel an expired eligible draw or another owner claim a ticket', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const {raffle}=await paidRaffle(e,{threshold:0});
  await send(raffle.connect(e.signers[1]).enterRaffle({value:100}));
  await e.provider.send('evm_increaseTime',[101]);await e.provider.send('evm_mine',[]);
  assert.equal(await raffle.isReadyToDraw(),true);
  await rejected(()=>raffle.connect(e.signers[2]).revertLottery.staticCall());
  await send(raffle.connect(e.signers[1]).revertLottery());
  await rejected(()=>raffle.connect(e.signers[2]).claimRefund.staticCall(1));
});

test('standalone ticket initialization cannot be front-run', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const nft=await e.deploy('RaffleNFT');
  await rejected(()=>nft.connect(e.signers[2]).initialize.staticCall(e.addresses[2],''));
  await send(nft.initialize(e.addresses[1],''));
  await rejected(()=>nft.initialize.staticCall(e.addresses[0],''));
});


test('GSN: both paymasters sponsor only the current entry selector and reject untrusted forwarders/value', async t => {
  const e=await environment();t.after(()=>e.rpc.disconnect());const forwarder=await e.deploy('MockForwarder');
  const hub=await e.deploy('MockRelayHub');const {promo,admission}=await promoRaffle(e,2,forwarder.target);
  const a=await admission();
  for(const name of ['Paymaster','PaymasterWhitelist']) {
    const paymaster=await e.deploy(name);await send(paymaster.setRelayHub(hub.target));await send(paymaster.setTrustedForwarder(forwarder.target));
    if(name==='Paymaster') await send(paymaster.setTarget(promo.target));else await send(paymaster.configurePromoRaffle(promo.target));
    const request={request:{from:e.addresses[1],to:promo.target,value:0,gas:500000,nonce:0,data:promo.interface.encodeFunctionData('enterRaffle',a.args),validUntilTime:0},
      relayData:{maxFeePerGas:0,maxPriorityFeePerGas:0,transactionCalldataGasUsed:0,relayWorker:e.addresses[3],paymaster:paymaster.target,forwarder:forwarder.target,paymasterData:'0x',clientId:0}};
    const encode = req=>paymaster.interface.encodeFunctionData('preRelayedCall',[req,'0x','0x',500000]);
    const result=await hub.invoke.staticCall(paymaster.target,encode(request));
    const decoded=paymaster.interface.decodeFunctionResult('preRelayedCall',result);assert.equal(decoded[1],true);
    for(const data of ['0x',promo.interface.encodeFunctionData('getCycle'),ethers.id('enterRaffle(bytes32,bytes2)').slice(0,10)]) {
      await rejected(()=>hub.invoke.staticCall(paymaster.target,encode({...request,request:{...request.request,data}})));
    }
    await rejected(()=>hub.invoke.staticCall(paymaster.target,encode({...request,request:{...request.request,value:1}})));
    await rejected(()=>hub.invoke.staticCall(paymaster.target,encode({...request,relayData:{...request.relayData,forwarder:e.addresses[4]}})));
  }
});
