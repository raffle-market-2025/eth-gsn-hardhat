//
// This script exactly matches your requested behavior:
//
// 1) reads core addresses from ./build/gsn, 
// 2) reads PromoRaffle from ./build/raffle/PromoRaffle.json, 
// 3) deploys and configures the Paymaster, 
// 4) optionally funds it (default 0.05 ETH), 
// 5) and prints RelayHub.balanceOf(paymaster).
//
import { network } from "hardhat";
import fs from "node:fs";
import path from "node:path";

type AddressJson = { address: string };

function readAddress(relPath: string): string {
  const abs = path.join(process.cwd(), relPath);
  if (!fs.existsSync(abs)) throw new Error(`Missing file: ${relPath}`);
  const j = JSON.parse(fs.readFileSync(abs, "utf8")) as Partial<AddressJson>;
  const a = j.address ?? "";
  if (!/^0x[a-fA-F0-9]{40}$/.test(a)) throw new Error(`Invalid address in ${relPath}: ${a}`);
  return a;
}

function writeAddress(relPath: string, address: string) {
  const abs = path.join(process.cwd(), relPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, JSON.stringify({ address }, null, 2) + "\n", "utf8");
  console.log(`Wrote ${relPath}: { "address": "${address}" }`);
}

// Minimal ABIs (string fragments) to avoid TypeChain dependency
const PAYMASTER_ABI = [
  "function setRelayHub(address relayHub) external",
  "function setTrustedForwarder(address forwarder) external",
  "function setTarget(address target) external",
  "function getRelayHub() view returns (address)",
  "function getTrustedForwarder() view returns (address)",
  "function ourTarget() view returns (address)",
] as const;

const ERC2771_RECIPIENT_ABI = [
  "function isTrustedForwarder(address forwarder) view returns (bool)",
] as const;

const RELAY_HUB_ABI = [
  "function balanceOf(address target) view returns (uint256)",
] as const;

async function main() {
//   if (network.name === "hardhat" || network.name === "localhost") {
//     console.log("promo-raffle-gsn: skip on local networks");
//     return;
//   }

  const { ethers } = await network.connect();

  const net = await ethers.provider.getNetwork();
  if (net.chainId !== 11155111n) {
    throw new Error(`Expected Sepolia chainId=11155111, got ${net.chainId.toString()}`);
  }

  // Inputs
  const promoRaffle = readAddress("build/raffle/PromoRaffle.json");
  const relayHub = readAddress("build/gsn/RelayHub.json");
  const forwarder = readAddress("build/gsn/Forwarder.json");

  // Funding (env or default)
  const fundEthStr = (process.env.PROMO_RAFFLE_PAYMASTER_FUND_ETH ?? "").trim() || "0.05";
  const fundEth = ethers.parseEther(fundEthStr);

  const [deployer] = await ethers.getSigners();

  console.log("Deployer   :", await deployer.getAddress());
  console.log("PromoRaffle:", promoRaffle);
  console.log("RelayHub   :", relayHub);
  console.log("Forwarder  :", forwarder);

  // 1) Deploy Paymaster
  const PaymasterFactory = await ethers.getContractFactory("Paymaster", deployer);
  const paymasterDeploy = await PaymasterFactory.deploy();
  console.log("Deploy Paymaster tx:", paymasterDeploy.deploymentTransaction()?.hash);

  await paymasterDeploy.waitForDeployment();
  const paymasterAddress = await paymasterDeploy.getAddress();
  console.log("Paymaster deployed at:", paymasterAddress);

  // ✅ Persist Paymaster address for other scripts (smoke test, UI, etc.)
  writeAddress("build/gsn/Paymaster.json", paymasterAddress);

  // 2) Re-bind with minimal ABI so TS sees methods
  const paymaster = new ethers.Contract(paymasterAddress, PAYMASTER_ABI, deployer) as any;

  console.log("Configuring Paymaster...");
  await (await paymaster.setRelayHub(relayHub)).wait();
  await (await paymaster.setTrustedForwarder(forwarder)).wait();
  await (await paymaster.setTarget(promoRaffle)).wait();
  console.log("Paymaster configured (relayHub/forwarder/target).");

  // 3) Sanity check: PromoRaffle trusts forwarder (constructor-fixed)
  const recipient = new ethers.Contract(promoRaffle, ERC2771_RECIPIENT_ABI, deployer) as any;
  const ok: boolean = await recipient.isTrustedForwarder(forwarder);
  console.log("PromoRaffle.isTrustedForwarder(forwarder) =", ok);
  if (!ok) {
    throw new Error(
      "PromoRaffle does NOT trust Forwarder from build/gsn/Forwarder.json. " +
        "Since forwarder is set in constructor, redeploy PromoRaffle with this forwarder."
    );
  }

  // 4) Optional: fund Paymaster (ETH -> BasePaymaster.receive() -> deposit to RelayHub in v3)
  if (fundEth > 0n) {
    console.log(`Funding Paymaster with ${fundEthStr} ETH...`);
    const fundTx = await deployer.sendTransaction({ to: paymasterAddress, value: fundEth });
    console.log("Fund tx:", fundTx.hash);
    await fundTx.wait();
    console.log("Paymaster funded.");
  } else {
    console.log("Skipping funding (PROMO_RAFFLE_PAYMASTER_FUND_ETH=0).");
  }

  // 5) Read deposit in RelayHub
  const hub = new ethers.Contract(relayHub, RELAY_HUB_ABI, deployer) as any;
  const dep: bigint = await hub.balanceOf(paymasterAddress);
  console.log("RelayHub.balanceOf(paymaster) =", ethers.formatEther(dep), "ETH");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});