import { network } from "hardhat";
import cfg from "../config/gsn-relay-config.json";

const RMT = (cfg as any).managerStakeTokenAddress as string;

const ABI = [
  "function buyTokens() payable",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

async function main() {
  const { ethers } = await network.connect();
  const [signer] = await ethers.getSigners();
  const owner = await signer.getAddress();

  const token = await ethers.getContractAt(ABI, RMT, signer);

  const sym = await token.symbol().catch(() => "TOKEN");
  const dec = await token.decimals().catch(() => 18);

  const before = await token.balanceOf(owner);
  console.log("Owner:", owner);
  console.log("Stake token:", RMT, `(${sym})`);
  console.log("Balance before:", ethers.formatUnits(before, dec), sym);

  const value = ethers.parseEther("0.001"); // 0.001 ETH => 10 RMT по вашему контракту
  const tx = await token.buyTokens({ value });
  console.log("buyTokens tx:", tx.hash);
  await tx.wait(1);

  const after = await token.balanceOf(owner);
  console.log("Balance after :", ethers.formatUnits(after, dec), sym);
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});
