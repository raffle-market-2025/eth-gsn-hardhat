import { network } from "hardhat";
import forwarderJson from "../build/gsn/Forwarder.json";

async function main() {
  const { ethers } = await network.connect();
  const forwarderAddress = (forwarderJson as any).address;

  console.log("Start deploy...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", await deployer.getAddress());

  const Factory = await ethers.getContractFactory("PromoRaffle");
  const args = [1, forwarderAddress, deployer.address];
  console.log("Deploying PromoRaffle with args:", args);

  const contract = await Factory.deploy(...args);
  console.log("Tx hash:", contract.deploymentTransaction()?.hash);

  await contract.waitForDeployment();
  console.log("PromoRaffle deployed at:", await contract.getAddress());
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});
