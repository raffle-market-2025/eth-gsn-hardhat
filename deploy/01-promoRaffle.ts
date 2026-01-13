import { network } from "hardhat";

import forwarderJson from "../build/gsn/Forwarder.json";
import writeAddressJson from "../utils/writeAddressJson.js";
import verifyWithRetries from "../utils/verifyWithRetries.js";

// Deploy logic:
// 1) Deploy PromoRaffle(playersNeeded, trustedForwarder, deployer)
// 2) Deploy RaffleNFT()  (NEW clone-friendly version: empty constructor)
// 3) promoNFT.initialize(promoRaffleAddress, baseURI)   <-- REQUIRED
// 4) promoRaffle.setPromoNftAddress(promoNFTAddress)
//
// Frontend sends tx via GSN RelayProvider with paymasterAddress = PromoRafflePaymaster.

async function main() {
  const { ethers } = await network.connect();

  const net = await ethers.provider.getNetwork();
  const isDev =
    net.chainId === 31337n ||
    net.name === "hardhat" ||
    net.name === "localhost";

  const waitConfirmations = isDev ? 1 : 5;

  const forwarderAddress = (forwarderJson as any).address as string;
  if (!forwarderAddress || forwarderAddress === ethers.ZeroAddress) {
    throw new Error("Forwarder address missing in ../build/gsn/Forwarder.json");
  }

  const baseURI =
    "ipfs://bafybeidh6xhjihvmkha6yuxyjol7ubccdmvx6i3m6vdc6pawkykjlcx2ju/promo.json";

  const promoFundAmount = ethers.parseEther("0.005"); // 0.005 ETH

  const asBytes2 = (s: string) => {
    const b = ethers.toUtf8Bytes(s);
    if (b.length < 2 || b.length > 2) {
      throw new Error("country2 must be 2 ASCII chars");
    }
    // right-pad to 2 bytes for bytes2
    const padded = new Uint8Array(2);
    padded.set(b, 0);
    return ethers.hexlify(padded); // e.g. "US" -> 0x5553
  };

  console.log("----------------------------------------------------");
  console.log("Start deploy...");
  console.log(`Network: ${net.name} (chainId=${net.chainId.toString()})`);

  const [deployer] = await ethers.getSigners();
  const deployerAddr = await deployer.getAddress();
  console.log("Deployer:", deployerAddr);

  // ------------------------------------------------------------
  // 1) Deploy PromoRaffle
  // ------------------------------------------------------------
  const FactoryPromo = await ethers.getContractFactory("PromoRaffle", deployer);

  const promoArgs: [bigint, string, string] = [1n, forwarderAddress, deployerAddr];
  console.log("Deploying PromoRaffle with args:", promoArgs);
  console.log("Initial funding (value):", promoFundAmount.toString(), "wei");

  const promoRaffle = await FactoryPromo.deploy(...promoArgs, {
    value: promoFundAmount,
  });

  console.log("PromoRaffle tx hash:", promoRaffle.deploymentTransaction()?.hash);
  await promoRaffle.waitForDeployment();

  const addressPromoRaffle = await promoRaffle.getAddress();
  console.log("PromoRaffle deployed at:", addressPromoRaffle);

  writeAddressJson("build/raffle/PromoRaffle.json", addressPromoRaffle);

  if (!isDev) {
    await verifyWithRetries(addressPromoRaffle, promoArgs);
  } else {
    console.log("Dev chain: skipping Etherscan verification for PromoRaffle.");
  }

  // ------------------------------------------------------------
  // 2) Deploy RaffleNFT (NEW: empty constructor)
  // ------------------------------------------------------------
  const FactoryNFT = await ethers.getContractFactory("RaffleNFT", deployer);

  console.log("Deploying RaffleNFT (no constructor args)...");
  const promoNFT = await FactoryNFT.deploy();

  console.log("RaffleNFT tx hash:", promoNFT.deploymentTransaction()?.hash);
  await promoNFT.waitForDeployment();

  const addressPromoNFT = await promoNFT.getAddress();
  console.log("PromoNFT deployed at:", addressPromoNFT);

  // 3) Initialize NFT (REQUIRED for new clone-friendly RaffleNFT)
  console.log("Initializing PromoNFT...");
  const initTx = await promoNFT.initialize(addressPromoRaffle, baseURI);
  console.log("PromoNFT.initialize tx hash:", initTx.hash);
  await initTx.wait(waitConfirmations);
  console.log("PromoNFT initialized.");

  writeAddressJson("build/raffle/PromoNFT.json", addressPromoNFT);

  if (!isDev) {
    // constructor args are empty for new RaffleNFT
    await verifyWithRetries(addressPromoNFT, []);
  } else {
    console.log("Dev chain: skipping Etherscan verification for PromoNFT.");
  }

  // ------------------------------------------------------------
  // 4) Register the PromoNFT address in the PromoRaffle contract
  // ------------------------------------------------------------
  console.log("Setting PromoNFT address in PromoRaffle...");
  const setTx = await promoRaffle.setPromoNftAddress(addressPromoNFT);
  console.log("PromoRaffle.setPromoNftAddress tx hash:", setTx.hash);
  await setTx.wait(waitConfirmations);
  console.log("PromoNFT address set in PromoRaffle.");

  console.log("----- PromoRaffle deployed -----------------------------------------------");

  // ------------------------------------------------------------
  // Optional: quick test run (same as your original, but kept working)
  // ------------------------------------------------------------
  const balanceWeiBefore = await ethers.provider.getBalance(deployerAddr);
  console.log(
    `Deployer balance before test run: ${ethers.formatEther(balanceWeiBefore)} ETH`
  );

  console.log("----- PromoRaffle test run started ---------------------------------------");

  const ipHash = ethers.keccak256(ethers.toUtf8Bytes("192.168.0.1"));
  const enterTx = await promoRaffle.enterRaffle(ipHash, asBytes2("US"));
  console.log("Entering PromoRaffle, tx hash:", enterTx.hash);
  await enterTx.wait(waitConfirmations);

  const playersEntered: bigint = await promoRaffle.getNumberOfPlayersEntered();
  console.log(
    "Number of players entered into PromoRaffle [ after-run, should be 0 ]:",
    playersEntered.toString()
  );

  const maxPlayers = 100n;
  const txMaxPlayers = await promoRaffle.updatePlayersNeeded(maxPlayers);
  console.log("Setting MaxPlayers in PromoRaffle, tx hash:", txMaxPlayers.hash);
  await txMaxPlayers.wait(waitConfirmations);

  const readMaxPlayers: bigint = await promoRaffle.getNumberOfPlayers();
  console.log("MaxPlayers in PromoRaffle set to", readMaxPlayers.toString());

  const txFund = await deployer.sendTransaction({
    to: addressPromoRaffle,
    value: promoFundAmount,
  });
  await txFund.wait(waitConfirmations);

  console.log(
    `PromoRaffle (${addressPromoRaffle}) funded with ${promoFundAmount.toString()} wei`
  );

  console.log("----- PromoRaffle configuration complete ---------------------------------");
  console.log("Done.");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});