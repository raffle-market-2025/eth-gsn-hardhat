import "dotenv/config";
import { network } from "hardhat";
import { formatEther, parseEther } from "ethers";

// Chainlink VRF v2.5 (Sepolia)
const DEFAULT_SEPOLIA_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";

const COORDINATOR_ABI = [
  "function fundSubscriptionWithNative(uint256 subId) external payable",
  "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] consumers)",
  "function addConsumer(uint256 subId, address consumer) external",
];

const MARKETPLACE_ABI = [
  // Your VRFV2SubscriptionManager exposes this (per your snippet)
  "function getSubscription() external view returns (uint256)",
];

function env(name: string): string | undefined {
  const v = process.env[name];
  return v && v.trim().length ? v.trim() : undefined;
}

async function main() {
  const { ethers } = await network.connect();
  const [signer] = await ethers.getSigners();

  const coordinatorAddress = env("VRF_COORDINATOR") ?? DEFAULT_SEPOLIA_COORDINATOR;

  // Either provide VRF_SUB_ID directly, or provide MARKETPLACE_ADDRESS to read it.
  let subIdStr = env("VRF_SUB_ID");
  const marketplaceAddress = env("MARKETPLACE_ADDRESS");

  if (!subIdStr && marketplaceAddress) {
    const marketplace = new ethers.Contract(marketplaceAddress, MARKETPLACE_ABI, signer);
    const subIdFromContract = await marketplace.getSubscription();
    subIdStr = subIdFromContract.toString();
    console.log(`Subscription ID (from marketplace): ${subIdStr}`);
  }

  if (!subIdStr) {
    throw new Error("Set VRF_SUB_ID or MARKETPLACE_ADDRESS in .env");
  }

  const subId = BigInt(subIdStr);

  const coordinator = new ethers.Contract(coordinatorAddress, COORDINATOR_ABI, signer);

  const [linkBalBefore, nativeBalBefore, reqCountBefore, ownerBefore, consumersBefore] =
    await coordinator.getSubscription(subId);

  console.log("=== BEFORE ===");
  console.log(`Coordinator:  ${coordinatorAddress}`);
  console.log(`SubId:        ${subId}`);
  console.log(`Owner:        ${ownerBefore}`);
  console.log(`Req count:    ${reqCountBefore}`);
  console.log(`LINK balance: ${formatEther(linkBalBefore)} LINK (juels)`);
  console.log(`Native bal:   ${formatEther(nativeBalBefore)} ETH`);
  console.log(`Consumers:    ${consumersBefore.length ? consumersBefore.join(", ") : "(none)"}`);

  // Fund with native ETH
  const amountEth = env("AMOUNT_NATIVE") ?? "0.05"; // default 0.05 ETH
  const value = parseEther(amountEth);

  console.log(`\nFunding with native: ${amountEth} ETH ...`);
  const tx = await coordinator.fundSubscriptionWithNative(subId, { value });
  console.log(`Tx hash: ${tx.hash}`);
  await tx.wait();

  const [linkBalAfter, nativeBalAfter, reqCountAfter, ownerAfter, consumersAfter] =
    await coordinator.getSubscription(subId);

  console.log("\n=== AFTER ===");
  console.log(`Owner:        ${ownerAfter}`);
  console.log(`Req count:    ${reqCountAfter}`);
  console.log(`LINK balance: ${formatEther(linkBalAfter)} LINK (juels)`);
  console.log(`Native bal:   ${formatEther(nativeBalAfter)} ETH`);
  console.log(`Consumers:    ${consumersAfter.length ? consumersAfter.join(", ") : "(none)"}`);

  // Optional: add a consumer in the same run (e.g., your deployed raffle contract)
  const maybeConsumer = env("ADD_CONSUMER");
  if (maybeConsumer) {
    console.log(`\nAdding consumer: ${maybeConsumer} ...`);
    const addTx = await coordinator.addConsumer(subId, maybeConsumer);
    console.log(`AddConsumer tx: ${addTx.hash}`);
    await addTx.wait();
    console.log("Consumer added.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
