import { network } from "hardhat";
import relayHubJson from "../build/gsn/RelayHub.json";

const { ethers } = await network.connect();
const RELAY_HUB = (relayHubJson as any).address as string;

const ABI = [
  "function setMinimumStakes(address[] token, uint256[] minimumStake) external",
  "function getMinimumStakePerToken(address token) view returns (uint256)"
];

async function main() {
  const token = process.env.TOKEN;
  const minStr = process.env.MIN ?? "1"; // 1 token by default
  if (!token) throw new Error("Set env TOKEN=0x...");

  const [signer] = await ethers.getSigners();
  console.log("Signer:", await signer.getAddress());
  console.log("RelayHub:", RELAY_HUB);

  const hub = await ethers.getContractAt(ABI, RELAY_HUB, signer);

  const minWei = ethers.parseUnits(minStr, 18); // assumes 18 decimals (OK for TestToken/RMT in your code)
  console.log("Setting minimum stake:", minStr, "token(s) =>", minWei.toString());

  const tx = await hub.setMinimumStakes([token], [minWei]);
  console.log("tx:", tx.hash);
  await tx.wait(2);

  const readBack = await hub.getMinimumStakePerToken(token);
  console.log("minStake now:", ethers.formatUnits(readBack, 18));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
