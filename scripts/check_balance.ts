import { network } from "hardhat";
import fs from "node:fs";

function readMnemonic(path = "./mnemonic.txt"): string {
  const raw = fs.readFileSync(path, "utf8").trim();
  // allow either plain words or "MNEMONIC=..."
  const m = raw.includes("=") ? raw.split("=").slice(1).join("=").trim() : raw;
  const words = m.split(/\s+/).filter(Boolean);
  if (words.length < 12) throw new Error(`Mnemonic looks invalid (words=${words.length})`);
  return words.join(" ");
}

async function main() {
  const { ethers } = await network.connect();

  const MNEMONIC_PATH = process.env.MNEMONIC_PATH ?? "./mnemonic.txt";
  const COUNT = Number(process.env.COUNT ?? "10");
  const BASE_PATH = process.env.DERIVATION_PATH ?? "m/44'/60'/0'/0";

  const mnemonic = readMnemonic(MNEMONIC_PATH);
  const provider = ethers.provider;

  console.log("RPC:", (provider as any)?._getConnection?.()?.url ?? "(hardhat provider)");
  console.log("Mnemonic file:", MNEMONIC_PATH);
  console.log("Derivation base:", BASE_PATH);
  console.log("");

  for (let i = 0; i < COUNT; i++) {
    const wallet = ethers.HDNodeWallet.fromPhrase(mnemonic, undefined, `${BASE_PATH}/${i}`).connect(provider);
    const addr = await wallet.getAddress();
    const bal = await provider.getBalance(addr);
    console.log(
      `${String(i).padStart(2, "0")}  ${addr}  ${ethers.formatEther(bal)} ETH`
    );
  }
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});
