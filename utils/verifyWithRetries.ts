import hre, { network } from "hardhat";
import { verifyContract } from "@nomicfoundation/hardhat-verify/verify";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function verifyWithRetries(address: string, constructorArgs: any[]) {
  const { ethers } = await network.connect();
  const net = await ethers.provider.getNetwork();

  // Skip verification on local networks
  const skip = new Set(["hardhat", "localhost"]);
  if (skip.has(net.name)) return;

  console.log(`Start verifying address ${address} on network ${net.name}...`);

  for (let attempt = 1; attempt <= 8; attempt++) {
    try {
      await verifyContract(
        {
            address,
            constructorArgs,
        },
        hre
      );

      //await hre.run("verify:verify", { address, constructorArguments });
      console.log(`Verified: ${address}`);
      return;
    } catch (e: any) {
      const msg = String(e?.message ?? e);

      // Treat "already verified" as success
      if (msg.toLowerCase().includes("already verified")) {
        console.log(`Already verified: ${address}`);
        return;
      }

      // Common transient: explorer not indexed yet → retry
      console.log(`Verify attempt ${attempt} failed: ${msg}`);
      await sleep(15_000);
    }
  }

  throw new Error(`Verification failed after retries for ${address}`);
}

export default verifyWithRetries;
