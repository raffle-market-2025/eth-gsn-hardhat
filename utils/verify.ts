import hre from "hardhat";
import { verifyContract } from "@nomicfoundation/hardhat-verify/verify";

const verify = async (
  contractAddress: string,
  args: unknown[] = []
): Promise<void> => {
  console.log("Verifying contract:", contractAddress);

  try {
    await verifyContract(
      {
        address: contractAddress,
        constructorArgs: args,
      },
      hre
    );

    console.log("Verification successful");
  } catch (e: any) {
    if (typeof e?.message === "string" && e.message.includes("Already Verified")) {
      console.log("Contract already verified");
    } else {
      console.error("Verification error:", e);
    }
  }
};

export default verify;
