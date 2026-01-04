import { network } from "hardhat";
import fs from "node:fs";
import path from "node:path";

import forwarderJson from "../build/gsn/Forwarder.json";
import verifyWithRetries from "../utils/verifyWithRetries.js";

function writeAddressJson(relPath: string, address: string) {
  const abs = path.join(process.cwd(), relPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });

  let existing: any = {};
  if (fs.existsSync(abs)) {
    try {
      existing = JSON.parse(fs.readFileSync(abs, "utf8"));
      if (existing == null || typeof existing !== "object") existing = {};
    } catch {
      existing = {};
    }
  }

  const out = { ...existing, address };
  fs.writeFileSync(abs, JSON.stringify(out, null, 2) + "\n", "utf8");
  console.log(`Wrote ${relPath}:`, out);
}

// NFT деплоится этим скриптом/фабрикой, логика такая:
// Deploy PromoRaffle
// Deploy RaffleNFT(baseURI, promoRaffleAddress, "Raffle NFT", "Lucky")
// Call promoRaffle.setPromoNftAddress(raffleNftAddress)
// @dev фронтенд отправляет транзакции через GSN RelayProvider с paymasterAddress = PromoRafflePaymaster.
//
async function main() {
  const asBytes3 = (s: string) => {
    const b = ethers.toUtf8Bytes(s);
    if (b.length > 3) throw new Error("country must be exactly 2 or 3 ASCII chars");
    // Важно: для bytes3 лучше всегда передавать 3 байта; здесь у вас UKR (3) — ок.
    return ethers.hexlify(b); // "UKR" -> "0x554b52"
  };

  const { ethers } = await network.connect();
  const forwarderAddress = (forwarderJson as any).address as string;
  const promoFundAmount = ethers.parseEther("0.005"); // 0.00500 ETH

  console.log("Start deploy...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", await deployer.getAddress());

  const Factory = await ethers.getContractFactory("PromoRaffle", deployer);
  const args: [number, string, string] = [1, forwarderAddress, deployer.address];
  console.log("Deploying PromoRaffle with args:", args);

  const promoRaffle = await (Factory as any).deploy(...args, {
    value: promoFundAmount,
  });

  const deployTx = promoRaffle.deploymentTransaction();
  console.log("Deploy promoRaffle tx hash:", deployTx?.hash);

  if (deployTx) await deployTx.wait(5);

  await promoRaffle.waitForDeployment();
  const addressPromoRaffle = await promoRaffle.getAddress();
  console.log("PromoRaffle deployed at:", addressPromoRaffle);

  // ✅ записываем адрес в ./build/raffle/PromoRaffle.json
  writeAddressJson("build/raffle/PromoRaffle.json", addressPromoRaffle);

  await verifyWithRetries(addressPromoRaffle, args);

  const FactoryNFT = await ethers.getContractFactory("RaffleNFT", deployer);
  const argsNFT: [string, string, string, string] = [
    "ipfs://bafybeidh6xhjihvmkha6yuxyjol7ubccdmvx6i3m6vdc6pawkykjlcx2ju/promo.json",
    addressPromoRaffle,
    "Raffle NFT",
    "Lucky",
  ];
  console.log("Deploying RaffleNFT with args:", argsNFT);

  const promoNFT = await FactoryNFT.deploy(...argsNFT);
  console.log("Tx hash:", promoNFT.deploymentTransaction()?.hash);

  await promoNFT.waitForDeployment();
  const addressPromoNFT = await promoNFT.getAddress();
  console.log("PromoNFT deployed at:", addressPromoNFT);

  await verifyWithRetries(addressPromoNFT, argsNFT);

  // Register the PromoNFT address in the PromoRaffle contract
  const promoRaffleContract = await ethers.getContractAt("PromoRaffle", addressPromoRaffle);
  const tx = await promoRaffleContract.setPromoNftAddress(addressPromoNFT);
  console.log("Setting PromoNFT address in PromoRaffle, tx hash:", tx.hash);
  await tx.wait();
  console.log("PromoNFT address set in PromoRaffle.");

  // ✅ записываем NFT адрес в ./build/raffle/PromoNFT.json
  writeAddressJson("build/raffle/PromoNFT.json", await promoNFT.getAddress());

  console.log("----- PromoRaffle deployed -----------------------------------------------");

  const balanceWeiBefore = await ethers.provider.getBalance(deployer);
  console.log(`Deployer balance before test run: ${ethers.formatEther(balanceWeiBefore)} ETH`);

  console.log("----- PromoRaffle test run started ---------------------------------------");

  const ipHash = ethers.keccak256(ethers.toUtf8Bytes("192.168.0.1"));
  const enterTx = await promoRaffleContract.enterRaffle(ipHash, asBytes3("USA"));
  console.log("Entering PromoRaffle, tx hash:", enterTx.hash);
  await enterTx.wait();

  const playersEntered: bigint = await promoRaffleContract.getNumberOfPlayersEntered();
  console.log("Number of players entered into PromoRaffle [ after-run, should be 0 ]:", playersEntered);

  const maxPlayers = 100;
  const txMaxPlayers = await promoRaffleContract.updatePlayersNeeded(maxPlayers);
  console.log("Setting MaxPlayers in PromoRaffle, tx hash:", txMaxPlayers.hash);
  await txMaxPlayers.wait();

  const readMaxPlayers: bigint = await promoRaffleContract.getNumberOfPlayers();
  console.log("MaxPlayers in PromoRaffle set to", readMaxPlayers);

  const txFund = await deployer.sendTransaction({
    to: addressPromoRaffle,
    value: promoFundAmount,
  });
  await txFund.wait();

  console.log(`PromoRaffle (${addressPromoRaffle}) funded with ${promoFundAmount.toString()} wei`);
  console.log("----- PromoRaffle configuration complete ------------------------");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});