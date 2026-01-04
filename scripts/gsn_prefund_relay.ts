import { network } from "hardhat";

type GetAddrResponse =
  | {
      relayManagerAddress?: string;
      relayWorkerAddress?: string;
      manager?: string;
      worker?: string;
    }
  | any;

function asAddr(v: unknown, name: string): string {
  if (typeof v !== "string") throw new Error(`Missing ${name} in /getaddr`);
  if (!/^0x[a-fA-F0-9]{40}$/.test(v)) throw new Error(`Bad ${name}: ${v}`);
  return v;
}

async function main() {
  const { ethers } = await network.connect();

  const RELAY_URL = process.env.RELAY_URL ?? "http://127.0.0.1:8090";
  const AMOUNT_ETH = process.env.AMOUNT_ETH ?? "0.05";

  const [funder] = await ethers.getSigners();
  const funderAddr = await funder.getAddress();

  console.log("Funder:", funderAddr);
  console.log("Relay URL:", RELAY_URL);
  console.log("Amount per address:", AMOUNT_ETH, "ETH");

  const r = await fetch(`${RELAY_URL}/getaddr`);
  if (!r.ok) throw new Error(`GET ${RELAY_URL}/getaddr failed: ${r.status} ${r.statusText}`);

  const j: GetAddrResponse = await r.json();

  // Some versions use relayManagerAddress/relayWorkerAddress, others may differ.
  const relayManager =
    j.relayManagerAddress ?? j.relayManager ?? j.manager ?? j.relayManager_address;
  const relayWorker =
    j.relayWorkerAddress ?? j.relayWorker ?? j.worker ?? j.relayWorker_address;

  const managerAddr = asAddr(relayManager, "relayManagerAddress");
  const workerAddr = asAddr(relayWorker, "relayWorkerAddress");

  console.log("RelayManager:", managerAddr);
  console.log("RelayWorker :", workerAddr);

  const amountWei = ethers.parseEther(AMOUNT_ETH);

  // balances before
  const balManagerBefore = await ethers.provider.getBalance(managerAddr);
  const balWorkerBefore = await ethers.provider.getBalance(workerAddr);

  console.log("Balances BEFORE:");
  console.log("  manager:", ethers.formatEther(balManagerBefore), "ETH");
  console.log("  worker :", ethers.formatEther(balWorkerBefore), "ETH");

  // send funds
  const tx1 = await funder.sendTransaction({ to: managerAddr, value: amountWei });
  console.log("Funding manager tx:", tx1.hash);
  await tx1.wait(1);

  const tx2 = await funder.sendTransaction({ to: workerAddr, value: amountWei });
  console.log("Funding worker  tx:", tx2.hash);
  await tx2.wait(1);

  // balances after
  const balManagerAfter = await ethers.provider.getBalance(managerAddr);
  const balWorkerAfter = await ethers.provider.getBalance(workerAddr);

  console.log("Balances AFTER:");
  console.log("  manager:", ethers.formatEther(balManagerAfter), "ETH");
  console.log("  worker :", ethers.formatEther(balWorkerAfter), "ETH");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});