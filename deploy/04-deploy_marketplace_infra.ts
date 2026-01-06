import { network } from "hardhat";

import { developmentChains, networkConfig } from "../helper-hardhat-config.js";
import writeAddressJson from "../utils/writeAddressJson.js";
import verifyWithRetries from "../utils/verifyWithRetries.js";

const VRF_COORDINATOR_V2PLUS_ABI = [
  "function createSubscription() external returns (uint64)",
  "function addConsumer(uint64 subId, address consumer) external",
  "function getSubscription(uint64 subId) external view returns (uint96 balance,uint96 nativeBalance,uint64 reqCount,address owner,address[] consumers)",
  "function fundSubscriptionWithNative(uint64 subId) external payable",
];

async function main() {
  const { ethers } = await network.connect();
  const [deployer] = await ethers.getSigners();

  // ✅ New style: take network from provider (ethers v6) and assert chainId
  const net = await ethers.provider.getNetwork();
  const isDev = developmentChains.includes(net.name as any);
  const waitConfirmations = 2;

  if (!isDev && net.chainId !== 11155111n) {
    throw new Error(
      `Expected Sepolia chainId=11155111, got ${net.chainId.toString()}`
    );
  }

  const cfg = !isDev ? networkConfig[11155111] : undefined;

  console.log("----------------------------------------------------");
  console.log(`Network: ${net.name} (chainId=${net.chainId.toString()})`);
  console.log(`Deployer: ${await deployer.getAddress()}`);

  // ============================================================
  // 1) Deploy RaffleMarketplace (must be first)
  // ============================================================
  console.log("Deploying RaffleMarketplace...");
  const MarketplaceFactory = await ethers.getContractFactory(
    "RaffleMarketplace",
    deployer
  );
  const marketplace = await MarketplaceFactory.deploy();
  console.log("Tx hash:", marketplace.deploymentTransaction()?.hash);
  await marketplace.waitForDeployment();
  const addressMarketplace = await marketplace.getAddress();
  console.log("RaffleMarketplace deployed at:", addressMarketplace);
  writeAddressJson("build/raffle/RaffleMarketplace.json", addressMarketplace);

  // ============================================================
  // 2) Deploy RaffleContract implementation (Clones target)
  // ============================================================
  console.log("Deploying RaffleContract (implementation)...");
  const RaffleImplFactory = await ethers.getContractFactory("RaffleContract", deployer);
  const raffleImpl = await RaffleImplFactory.deploy();
  console.log("Tx hash:", raffleImpl.deploymentTransaction()?.hash);
  await raffleImpl.waitForDeployment();
  const addressRaffleImpl = await raffleImpl.getAddress();
  console.log("RaffleContract implementation deployed at:", addressRaffleImpl);
  writeAddressJson("build/raffle/RaffleContractImplementation.json", addressRaffleImpl);

  // ============================================================
  // 3) Deploy Verifier(marketplace, implementation)
  // ============================================================
  console.log("Deploying Verifier...");
  const VerifierFactory = await ethers.getContractFactory("Verifier", deployer);
  const verifierArgs: [string, string] = [addressMarketplace, addressRaffleImpl];
  console.log("Deploying Verifier with args:", verifierArgs);

  const verifier = await VerifierFactory.deploy(...verifierArgs);
  console.log("Tx hash:", verifier.deploymentTransaction()?.hash);
  await verifier.waitForDeployment();
  const addressVerifier = await verifier.getAddress();
  console.log("Verifier deployed at:", addressVerifier);
  writeAddressJson("build/raffle/Verifier.json", addressVerifier);

  // ============================================================
  // Dev-only shortcut (optional)
  // ============================================================
  if (isDev) {
    console.log("Dev chain detected: skipping Sepolia VRF/Automation infra.");
    console.log("You can deploy mocks or run a separate local infra script.");
    console.log("Done.");
    return;
  }

  // ============================================================
  // 4) VRF v2.5 Subscription (create or reuse)
  // ============================================================
  if (!cfg) throw new Error("Missing networkConfig for Sepolia");

  const coordinator = new ethers.Contract(
    cfg.vrfCoordinatorV2Plus,
    VRF_COORDINATOR_V2PLUS_ABI,
    deployer
  );

  let subId: bigint;
  const envSubId = process.env.VRF_SUBSCRIPTION_ID;

  if (envSubId && envSubId !== "0") {
    subId = BigInt(envSubId);
    console.log(`Using existing VRF subscriptionId from env: ${subId.toString()}`);
  } else {
    console.log("Creating VRF v2.5 subscription (Sepolia)...");
    const predicted: bigint = await coordinator.createSubscription.staticCall();
    const tx = await coordinator.createSubscription();
    await tx.wait(waitConfirmations);
    subId = predicted;
    console.log(`Created VRF subscriptionId: ${subId.toString()}`);
  }

  // ============================================================
  // 5) Deploy RaffleAutomationVRF(...)
  // ============================================================
  console.log("Deploying RaffleAutomationVRF...");

  const AutomationFactory = await ethers.getContractFactory("RaffleAutomationVRF", deployer);
  const automationArgs: [
    string,
    string,
    bigint,
    `0x${string}`,
    number,
    string,
    string,
    number,
    number
  ] = [
    addressMarketplace,
    cfg.vrfCoordinatorV2Plus,
    subId,
    cfg.vrfKeyHash,
    cfg.vrfCallbackGasLimit,
    cfg.linkToken,
    cfg.automationRegistrar,
    cfg.automationMaxBatch,
    cfg.automationMaxScan,
  ];

  console.log("Deploying RaffleAutomationVRF with args:", automationArgs);
  const automation = await AutomationFactory.deploy(...automationArgs);
  console.log("Tx hash:", automation.deploymentTransaction()?.hash);
  await automation.waitForDeployment();
  const addressAutomation = await automation.getAddress();
  console.log("RaffleAutomationVRF deployed at:", addressAutomation);
  writeAddressJson("build/raffle/RaffleAutomationVRF.json", addressAutomation);

  // ============================================================
  // 6) Wiring: marketplace.setVerifier + marketplace.setAutomation + VRF addConsumer
  // ============================================================
  console.log("Wiring infra...");

  const marketplaceWrite = new ethers.Contract(
    addressMarketplace,
    [
      "function setVerifier(address) external",
      "function setAutomation(address) external",
    ],
    deployer
  );

  try {
    const tx = await marketplaceWrite.setVerifier(addressVerifier);
    await tx.wait(waitConfirmations);
    console.log("Marketplace.setVerifier OK");
  } catch (e: any) {
    console.log(`Marketplace.setVerifier skipped/failed: ${e?.message ?? String(e)}`);
  }

  try {
    const tx = await marketplaceWrite.setAutomation(addressAutomation);
    await tx.wait(waitConfirmations);
    console.log("Marketplace.setAutomation OK");
  } catch (e: any) {
    console.log(`Marketplace.setAutomation skipped/failed: ${e?.message ?? String(e)}`);
  }

  try {
    const tx = await coordinator.addConsumer(subId, addressAutomation);
    await tx.wait(waitConfirmations);
    console.log("VRFCoordinator.addConsumer(Automation) OK");
  } catch (e: any) {
    console.log(`VRFCoordinator.addConsumer skipped/failed: ${e?.message ?? String(e)}`);
  }

  // Optional: initial native funding via Automation helper
  const fundWei = process.env.AUTOMATION_FUND_WEI;
  if (fundWei && fundWei !== "0") {
    try {
      const automationWrite = new ethers.Contract(
        addressAutomation,
        ["function fundSubscriptionNative() external payable"],
        deployer
      );
      const tx = await automationWrite.fundSubscriptionNative({ value: BigInt(fundWei) });
      await tx.wait(waitConfirmations);
      console.log(`Automation.fundSubscriptionNative OK: ${fundWei} wei`);
    } catch (e: any) {
      console.log(`Automation.fundSubscriptionNative skipped/failed: ${e?.message ?? String(e)}`);
    }
  }

  // ============================================================
  // 7) Verify (Sepolia only)
  // ============================================================
  console.log("----------------------------------------------------");
  console.log("Etherscan verification (with retries)...");

  await verifyWithRetries(addressMarketplace, []);
  await verifyWithRetries(addressRaffleImpl, []);
  await verifyWithRetries(addressVerifier, verifierArgs);
  await verifyWithRetries(addressAutomation, automationArgs as any);

  console.log("----------------------------------------------------");
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});