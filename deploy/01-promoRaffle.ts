import { network } from "hardhat";
import forwarderJson from "../build/gsn/Forwarder.json";
import verifyWithRetries from "../utils/verifyWithRetries.js";

async function main() {
  const asBytes3 = (s: string) => {
    const b = ethers.toUtf8Bytes(s);
    if (b.length > 3) throw new Error("country must be exactly 2 or 3 ASCII chars");
    return ethers.hexlify(b); // "UKR" -> "0x554b52"
  };

  const { ethers } = await network.connect();
  const forwarderAddress = (forwarderJson as any).address;
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

  // Wait a few confirmations before verifying (reduces “not indexed yet” failures)
  if (deployTx) await deployTx.wait(5);

  await promoRaffle.waitForDeployment();
  const addressPromoRaffle = await promoRaffle.getAddress();
  console.log("PromoRaffle deployed at:", addressPromoRaffle);
  await verifyWithRetries(addressPromoRaffle, args);

  const FactoryNFT = await ethers.getContractFactory("PromoNFT", deployer);
  const baseTokenURI: string = "ipfs://bafybeidh6xhjihvmkha6yuxyjol7ubccdmvx6i3m6vdc6pawkykjlcx2ju/promo.json";
  const argsNFT: [string, string] = [baseTokenURI, await promoRaffle.getAddress()];
  console.log("Deploying PromoNFT with args:", argsNFT);

  const promoNFT = await FactoryNFT.deploy(...argsNFT);
  console.log("Tx hash:", promoNFT.deploymentTransaction()?.hash);

  await promoNFT.waitForDeployment();
  const addressPromoNFT = await promoNFT.getAddress();
  console.log("PromoNFT deployed at:", addressPromoNFT);
  await verifyWithRetries(addressPromoNFT, argsNFT);

  // Register the PromoNFT address in the PromoRaffle contract
  const promoRaffleContract = await ethers.getContractAt("PromoRaffle", await promoRaffle.getAddress());
  const tx = await promoRaffleContract.setPromoNftAddress(await promoNFT.getAddress());
  console.log("Setting PromoNFT address in PromoRaffle, tx hash:", tx.hash);
  await tx.wait();
  console.log("PromoNFT address set in PromoRaffle.");

  // Ethernal integration
  // if ((network as any).config?.ethernal?.disabled !== true) {
  //   console.log("Pushing contracts to Ethernal...");
  //   await (network as any).ethernal.push({
  //     name: "PromoRaffle",
  //     address: await promoRaffle.getAddress(),
  //   });
  //   await (network as any).ethernal.push({
  //     name: "PromoNFT",
  //     address: await promoNFT.getAddress(),
  //   });
  //   console.log("Contracts pushed to Ethernal.");
  // }

  console.log("----- PromoRaffle deployed -----------------------------------------------");

  // read deployer balance before test run
  const balanceWeiBefore = await ethers.provider.getBalance(deployer);
  const balanceEthBefore = ethers.formatEther(balanceWeiBefore);
  console.log(`Deployer balance before test run: ${balanceEthBefore} ETH`);

  //
  // test run EnterRaffle and setting max players
  //
  console.log("----- PromoRaffle test run started ---------------------------------------");

  const enterTx = await promoRaffleContract.enterRaffle("192.168.0.1", asBytes3("UKR"));
  console.log("Entering PromoRaffle, tx hash:", enterTx.hash);
  await enterTx.wait();
  const playersEntered: bigint = await promoRaffleContract.getNumberOfPlayersEntered();
  console.log("Number of players entered into PromoRaffle [ after-run, should be 0 ]:", playersEntered);

  const maxPlayers: number = 100;
  const txMaxPlayers = await promoRaffleContract.updatePlayersNeeded(maxPlayers);
  console.log("Setting MaxPlayers in PromoRaffle, tx hash:", txMaxPlayers.hash);
  await txMaxPlayers.wait();
  const readMaxPlayers: bigint = await promoRaffleContract.getNumberOfPlayers();
  console.log("MaxPlayers in PromoRaffle set to", readMaxPlayers);

  const txFund = await deployer.sendTransaction({
    to: promoRaffle.getAddress(),
    value: promoFundAmount,
  });
  await txFund.wait();

  console.log(`PromoRaffle (${promoRaffle.getAddress()}) funded with ${promoFundAmount.toString()} wei`);
  console.log("----- PromoRaffle configuration complete ------------------------");
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});
