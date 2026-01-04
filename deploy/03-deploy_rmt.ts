import fs from "node:fs";
import path from "node:path";
import { network } from "hardhat";
import forwarderJson from "../build/gsn/Forwarder.json";
import verifyWithRetries from "../utils/verifyWithRetries.js";

type AddrJson = { address: string };

function isAddress(a: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(a);
}

function writeAddress(relPath: string, address: string) {
  const abs = path.join(process.cwd(), relPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  const payload: AddrJson = { address };
  fs.writeFileSync(abs, JSON.stringify(payload, null, 2));
  console.log(`Wrote ${relPath}:`, payload);
}

async function main() {
  const { ethers } = await network.connect();

  const forwarder = (forwarderJson as any).address as string;
  if (!forwarder || !isAddress(forwarder)) {
    throw new Error(
      `Bad Forwarder address in build/gsn/Forwarder.json: ${forwarder}`
    );
  }

  const [deployer] = await ethers.getSigners();
  console.log("Network:", network.name);
  console.log("Deployer:", await deployer.getAddress());
  console.log("Forwarder:", forwarder);

  // RMT constructor: (address trustedForwarder_)
  const args: [string] = [forwarder];

  const Factory = await ethers.getContractFactory("RMT", deployer);
  console.log("Deploying RMT with args:", args);

  const rmt = await (Factory as any).deploy(...args);
  const deployTx = rmt.deploymentTransaction();
  console.log("Deploy tx hash:", deployTx?.hash);

  // wait a few confirmations for better verify reliability
  if (deployTx) await deployTx.wait(5);

  await rmt.waitForDeployment();
  const rmtAddress = await rmt.getAddress();
  console.log("RMT deployed at:", rmtAddress);

  writeAddress("build/token/RMT.json", rmtAddress);

  // verify only on real networks
  if (network.name !== "hardhat" && network.name !== "localhost") {
    await verifyWithRetries(rmtAddress, args);
  }

  console.log("Done.");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});