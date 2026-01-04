import { network } from "hardhat";
import relayHubJson from "../build/gsn/RelayHub.json";

const { ethers } = await network.connect();
const RELAY_HUB = (relayHubJson as any).address as string;

const ABI = [
  "function getMinimumStakePerToken(address token) view returns (uint256)"
];

async function main() {
  const token = process.env.TOKEN;
  if (!token) throw new Error("Set env TOKEN=0x...");

  const hub = await ethers.getContractAt(ABI, RELAY_HUB);
  const min = await hub.getMinimumStakePerToken(token);
  console.log("RelayHub:", RELAY_HUB);
  console.log("Token  :", token);
  console.log("minStake (raw):", min.toString());
  console.log("minStake (18d):", ethers.formatUnits(min, 18));
  console.log("ALLOWED:", min > 0n);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
