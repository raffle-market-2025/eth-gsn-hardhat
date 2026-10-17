import fs from "node:fs";
import path from "node:path";

import { RelayProvider } from "@opengsn/provider";
import { network } from "hardhat";

// ethers v5
import { Web3Provider } from "@ethersproject/providers";
import { Contract } from "@ethersproject/contracts";
import { Interface } from "@ethersproject/abi";
import { formatEther } from "@ethersproject/units";
import { Wallet } from "@ethersproject/wallet";
import { keccak256 } from "@ethersproject/keccak256";
import { toUtf8Bytes } from "@ethersproject/strings";

type AddressJson = { address: string };

function readAddr(rel: string): string {
  const p = path.join(process.cwd(), rel);
  if (!fs.existsSync(p)) throw new Error(`Missing file: ${rel}`);
  const j = JSON.parse(fs.readFileSync(p, "utf8")) as Partial<AddressJson>;
  const a = j.address ?? "";
  if (!/^0x[a-fA-F0-9]{40}$/.test(a)) throw new Error(`Bad address in ${rel}: ${a}`);
  return a;
}

function bytes2FromAscii(code: string): string {
  const b = Buffer.from(code, "utf8");
  if (b.length !== 2) throw new Error("COUNTRY2 must contain exactly two ASCII bytes");
  return "0x" + b.toString("hex");
}

// IP -> bytes32 hash (Solidity-style: keccak256(bytes(ipString)))
function ipHashFromString(ip: string): string {
  const norm = ip.trim(); // если в контракте делаете другую нормализацию — меняйте тут
  return keccak256(toUtf8Bytes(norm));
}

// Light .env loader without dotenv
function loadDotEnv(file = ".env") {
  const abs = path.join(process.cwd(), file);
  if (!fs.existsSync(abs)) return;
  const lines = fs.readFileSync(abs, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const s = line.trim();
    if (!s || s.startsWith("#")) continue;
    const i = s.indexOf("=");
    if (i < 0) continue;
    const k = s.slice(0, i).trim();
    let v = s.slice(i + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    if (!(k in process.env)) process.env[k] = v;
  }
}

/**
 * Underlying provider for OpenGSN using Hardhat ethers.provider.send().
 * OpenGSN expects web3-style provider with send/sendAsync(payload, cb).
 */
class HardhatRpcBridge {
  constructor(private readonly hhProvider: { send: (method: string, params: any[]) => Promise<any> }) {}

  send(payload: any, cb: (err: any, resp: any) => void) {
    this.hhProvider
      .send(payload.method, payload.params ?? [])
      .then((result) => cb(null, { jsonrpc: "2.0", id: payload.id, result }))
      .catch((err) => cb(err, null));
  }

  sendAsync(payload: any, cb: (err: any, resp: any) => void) {
    this.send(payload, cb);
  }
}

/**
 * Adapter: GSN provider -> ethers v5 Web3Provider external provider.
 * send(method, params) must return RESULT (not full JSON-RPC object).
 */
function makeEthersV5ExternalProvider(gsnProvider: any, accounts: string[]) {
  const call = async (method: string, params?: any[]) => {
    if (method === "eth_accounts" || method === "eth_requestAccounts") {
      return accounts;
    }

    const payload = {
      jsonrpc: "2.0",
      id: Date.now(),
      method,
      params: params ?? [],
    };

    const resp: any = await new Promise((resolve, reject) => {
      const fn = gsnProvider.sendAsync ?? gsnProvider.send;
      if (typeof fn !== "function") return reject(new Error("GSN provider has no send/sendAsync"));
      fn.call(gsnProvider, payload, (err: any, res: any) => (err ? reject(err) : resolve(res)));
    });

    if (resp && typeof resp === "object" && "result" in resp) return resp.result;
    return resp;
  };

  return {
    request: ({ method, params }: { method: string; params?: any[] }) => call(method, params),
    send: (method: string, params?: any[]) => call(method, params),
    // legacy passthrough
    sendAsync: (payload: any, cb: (err: any, res: any) => void) => {
      const fn = gsnProvider.sendAsync ?? gsnProvider.send;
      return fn.call(gsnProvider, payload, cb);
    },
  };
}

async function main() {
  loadDotEnv(".env");

  // --- addresses from ./build ---
  const PROMO_RAFFLE = readAddr("build/raffle/PromoRaffle.json");
  const PAYMASTER = readAddr("build/gsn/Paymaster.json");
  const RELAY_HUB = readAddr("build/gsn/RelayHub.json");
  const FORWARDER = readAddr("build/gsn/Forwarder.json");

  // Optional fixed identity
  const pk = (process.env.SIGNER_PRIVATE_KEY ?? "").trim();

  // Underlying provider: proxy to hardhat ethers.provider
  const { ethers } = await network.connect();
  const underlying = new HardhatRpcBridge(ethers.provider as any);

  const gsnConfig: any = {
    paymasterAddress: PAYMASTER,
    relayHubAddress: RELAY_HUB,
    forwarderAddress: FORWARDER,
    auditorsCount: 0,
    loggerConfiguration: { logLevel: "debug" },
    performDryRunViewRelayCall: true,
  };

  const gsnProvider: any = await RelayProvider.newProvider({
    provider: underlying as any,
    config: gsnConfig,
  }).init();

  // Ensure GSN “from” account
  let from: string;
  if (pk) {
    gsnProvider.addAccount(pk);
    from = new Wallet(pk).address;
  } else {
    throw new Error("Set SIGNER_PRIVATE_KEY for the participant address authorized by the admission service");
  }

  const external = makeEthersV5ExternalProvider(gsnProvider, [from]);
  const provider = new Web3Provider(external as any);

  const chainIdHex = await provider.send("eth_chainId", []);
  console.log("chainId:", chainIdHex);

  console.log("Resolved:");
  console.log({
    promoRaffle: PROMO_RAFFLE,
    paymaster: PAYMASTER,
    relayHub: RELAY_HUB,
    forwarder: FORWARDER,
    from,
  });

  const promoAbi = [
    "function enterRaffle(bytes32 ipHash, bytes2 country2, uint256 deadline, bytes signature) external",
    "function isTrustedForwarder(address forwarder) view returns (bool)",
    "event RaffleEnter(address indexed _player, bytes32 _ipHash, bytes2 _country2, uint256 _lastTimestamp, uint256 cycle)",
  ];

  // Sanity: recipient trusts forwarder
  const ro = new Contract(PROMO_RAFFLE, promoAbi, provider);
  const trusts: boolean = await ro.isTrustedForwarder(FORWARDER);
  console.log("PromoRaffle trusts forwarder:", trusts);
  if (!trusts) throw new Error("PromoRaffle does NOT trust Forwarder from build/gsn/Forwarder.json");

  // Paymaster deposit BEFORE
  const hub = new Contract(RELAY_HUB, ["function balanceOf(address) view returns (uint256)"], provider);
  const depBefore = await hub.balanceOf(PAYMASTER);
  console.log("RelayHub.balanceOf(paymaster) BEFORE:", formatEther(depBefore), "ETH");

  // Send enterRaffle via GSN signer
  const signer = provider.getSigner(from);
  const promo = new Contract(PROMO_RAFFLE, promoAbi, signer);

  // Obtain these fields from the admission service for this exact `from` address.
  const ipHash = process.env.IP_HASH;
  const signature = process.env.PROMO_ENTRY_SIGNATURE;
  const deadline = process.env.PROMO_ENTRY_DEADLINE;
  if (!ipHash || !signature || !deadline) throw new Error("Set IP_HASH, PROMO_ENTRY_SIGNATURE and PROMO_ENTRY_DEADLINE from the admission service");
  const country = bytes2FromAscii(process.env.COUNTRY2 ?? "UA");
  const tx = await promo.enterRaffle(ipHash, country, deadline, signature);
  console.log("tx hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("mined block:", receipt.blockNumber, "status:", receipt.status);
  console.log("receipt.to (often RelayHub):", receipt.to);
  console.log("receipt.from (relay worker):", receipt.from);

  // Decode event to prove _msgSender()
  const iface = new Interface(promoAbi);
  const enterTopic = iface.getEventTopic("RaffleEnter");
  const log = receipt.logs.find(
    (l: any) =>
      String(l.address).toLowerCase() === PROMO_RAFFLE.toLowerCase() && l.topics?.[0] === enterTopic
  );

  if (!log) {
    console.log("WARN: RaffleEnter not found in logs.");
  } else {
    const parsed = iface.parseLog(log);
    const player = String(parsed.args._player ?? parsed.args[0]);
    const loggedIpHash = String(parsed.args._ipHash ?? parsed.args[1]);
    console.log("RaffleEnter._player:", player);
    console.log("RaffleEnter._ipHash :", loggedIpHash);
    console.log("matches expected player:", player.toLowerCase() === from.toLowerCase());
    console.log("matches expected ipHash:", loggedIpHash.toLowerCase() === ipHash.toLowerCase());
  }

  const depAfter = await hub.balanceOf(PAYMASTER);
  console.log("RelayHub.balanceOf(paymaster) AFTER:", formatEther(depAfter), "ETH");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});