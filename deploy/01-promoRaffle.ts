import { network } from "hardhat";
import forwarderJson from "../build/gsn/Forwarder.json";
import writeAddressJson from "../utils/writeAddressJson.js";

const required = (name: string) => {
  const value = process.env[name];
  if (!value) throw new Error(`Set ${name} before deploying`);
  return value;
};

async function main() {
  const { ethers } = await network.connect();
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const coordinatorAddress = required("PROMO_VRF_COORDINATOR");
  const subscriptionId = BigInt(required("PROMO_VRF_SUBSCRIPTION_ID"));
  const entrySigner = required("PROMO_ENTRY_SIGNER");
  const coordinator = new ethers.Contract(coordinatorAddress, [
    "function getSubscription(uint256) view returns(uint96,uint96,uint64,address,address[])",
    "function addConsumer(uint256,address)",
  ], deployer);
  const subscription = await coordinator.getSubscription(subscriptionId);
  if (subscription[3].toLowerCase() !== deployerAddress.toLowerCase()) {
    throw new Error("The deployer must own the configured subscription to authorize the promo consumer");
  }
  const config = {
    coordinator: coordinatorAddress, subscriptionId,
    keyHash: required("PROMO_VRF_KEY_HASH"),
    callbackGasLimit: Number(process.env.PROMO_VRF_CALLBACK_GAS_LIMIT ?? "150000"),
    entrySigner,
  };
  const factory = await ethers.getContractFactory("PromoRaffle", deployer);
  const promo = await factory.deploy(
    BigInt(process.env.PROMO_PLAYERS_NEEDED ?? "100"),
    (forwarderJson as any).address, deployerAddress, config,
    { value: ethers.parseEther(process.env.PROMO_FUND_ETH ?? "0.005") },
  );
  await promo.waitForDeployment();
  await (await coordinator.addConsumer(subscriptionId, await promo.getAddress())).wait();
  const nft = await ethers.deployContract("RaffleNFT");
  await nft.waitForDeployment();
  await (await nft.initialize(await promo.getAddress(), process.env.PROMO_BASE_URI ?? "")).wait();
  await (await promo.setPromoNftAddress(await nft.getAddress())).wait();
  writeAddressJson("build/raffle/PromoRaffle.json", await promo.getAddress());
  writeAddressJson("build/raffle/PromoNFT.json", await nft.getAddress());
  console.log("Promo deployed:", await promo.getAddress());
  console.log("Fund the VRF subscription with native ETH and register checkUpkeep/performUpkeep for finalization.");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
