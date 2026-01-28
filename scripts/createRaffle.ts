import { network } from "hardhat";
import fs from "fs";
import path from "path";

import { developmentChains, networkConfig } from "../helper-hardhat-config.js";

function readAddressJson(relPath: string): string {
  const abs = path.join(process.cwd(), relPath);
  const raw = JSON.parse(fs.readFileSync(abs, "utf8"));
  const addr = (raw?.address ?? "").toString();
  if (!addr || !addr.startsWith("0x")) {
    throw new Error(`Bad address in ${relPath}: ${JSON.stringify(raw)}`);
  }
  return addr;
}

function asBytes2(ethers: any, s: string): string {
  const b: Uint8Array = ethers.toUtf8Bytes(s);
  if (b.length !== 2) {
    throw new Error("country2 must be exactly 2 ASCII chars (ISO-3166-1 alpha-2), e.g. 'UA', 'US'");
  }
  // ethers v6 FixedBytesCoder требует ровно 2 байта
  return ethers.hexlify(b); // "UA" -> "0x5541"
}

async function main() {
  const { ethers } = await network.connect();

  // ✅ New style: take network from provider (ethers v6) and assert chainId
  const net = await ethers.provider.getNetwork();
  const isDev =
    developmentChains.includes(net.name as any) ||
    net.chainId === 31337n ||
    net.chainId === 1337n;

  const waitConfirmations = 2;

  if (!isDev && net.chainId !== 11155111n) {
    throw new Error(
      `Expected Sepolia chainId=11155111, got ${net.chainId.toString()}`
    );
  }

  const cfg = !isDev ? networkConfig[11155111] : undefined;
  void cfg;

  const [deployer] = await ethers.getSigners();
  const deployerAddr = await deployer.getAddress();

  console.log("----------------------------------------------------");
  console.log(`Network: ${net.name} (chainId=${net.chainId.toString()})`);
  console.log(`Deployer: ${deployerAddr}`);

  // Prefer env override, else read from build json
  const marketplaceAddress =
    process.env.MARKETPLACE_ADDRESS ??
    readAddressJson("build/raffle/RaffleMarketplace.json");

  console.log("Marketplace:", marketplaceAddress);

  // Marketplace ABI (минимально нужное)
  const MARKET_ABI = [
    "function owner() view returns (address)",
    "function verifier() view returns (address)",
    "function automation() view returns (address)",
    "function raffleNftImplementation() view returns (address)",

    "function setVerifier(address) external",
    "function setAutomation(address) external",
    "function setRaffleNftImplementation(address) external",

    // createRaffle(prizes: (string,bytes2,uint256)[], stages: (uint8,uint256,uint256,uint256)[])
    "function createRaffle(uint256 durationSeconds,uint256 thresholdPercent,(string,bytes2,uint256)[] prizes,(uint8,uint256,uint256,uint256)[] stages,string nftBaseURI,string nftName,string nftSymbol) returns (uint256 raffleId,address raffleAddr)",
  ] as const;

  const marketplace = new ethers.Contract(
    marketplaceAddress,
    MARKET_ABI,
    deployer
  );

  const Z = "0x0000000000000000000000000000000000000000";

  // -----------------------------
  // Preflight: check wiring
  // -----------------------------
  const mpOwner: string = await marketplace.owner();
  const curVerifier: string = await marketplace.verifier();
  const curAutomation: string = await marketplace.automation();
  const curNftImpl: string = await marketplace.raffleNftImplementation();

  console.log("Wiring:");
  console.log(" owner:", mpOwner);
  console.log(" verifier:", curVerifier);
  console.log(" automation:", curAutomation);
  console.log(" raffleNftImplementation:", curNftImpl);

  // Optional auto-wiring (если деплоер = owner и вы передали адреса через env)
  // Это удобно, если забыли добавить setRaffleNftImplementation в infra-deploy.
  const canWire = mpOwner.toLowerCase() === deployerAddr.toLowerCase();

  const verifierFromEnv = (process.env.VERIFIER_ADDRESS ?? "").trim();
  const automationFromEnv = (process.env.AUTOMATION_ADDRESS ?? "").trim();
  const nftImplFromEnv = (process.env.RAFFLE_NFT_IMPL_ADDRESS ?? "").trim();

  if (canWire) {
    if (curVerifier === Z && verifierFromEnv) {
      console.log("Setting verifier from env...");
      const tx = await marketplace.setVerifier(verifierFromEnv);
      console.log(" tx:", tx.hash);
      await tx.wait(waitConfirmations);
    }
    if (curAutomation === Z && automationFromEnv) {
      console.log("Setting automation from env...");
      const tx = await marketplace.setAutomation(automationFromEnv);
      console.log(" tx:", tx.hash);
      await tx.wait(waitConfirmations);
    }
    if (curNftImpl === Z && nftImplFromEnv) {
      console.log("Setting raffleNftImplementation from env...");
      const tx = await marketplace.setRaffleNftImplementation(nftImplFromEnv);
      console.log(" tx:", tx.hash);
      await tx.wait(waitConfirmations);
    }
  }

  // Re-check after optional wiring
  const verifier2: string = await marketplace.verifier();
  const automation2: string = await marketplace.automation();
  const nftImpl2: string = await marketplace.raffleNftImplementation();

  if (verifier2 === Z) throw new Error("Marketplace__VerifierNotSet(): verifier is not set");
  if (automation2 === Z) throw new Error("Marketplace__AutomationNotSet(): automation is not set");
  if (nftImpl2 === Z) {
    throw new Error(
      "Marketplace__NftImplNotSet(): raffleNftImplementation is not set.\n" +
        "Call marketplace.setRaffleNftImplementation(<RaffleNFT implementation address>) once from marketplace owner,\n" +
        "or pass env RAFFLE_NFT_IMPL_ADDRESS and rerun."
    );
  }

  // -----------------------------
  // Params (edit as needed)
  // -----------------------------
  const durationSeconds = 60 * 60 * 24 * 3; // 3 days
  const thresholdPercent = 60; // 60%

  // prizes: (string prizeTitle, bytes2 country2, uint256 prizeAmount)
  const prizes: Array<[string, string, bigint]> = [
    ["1st Prize", asBytes2(ethers, "UA"), ethers.parseEther("0.001")],
    ["2nd Prize", asBytes2(ethers, "US"), ethers.parseEther("0.005")],
  ];

  // stages: (uint8 stageType, uint256 ticketsAvailable, uint256 ticketPrice, uint256 ticketsSold)
  // IMPORTANT: ticketsSold must be 0 on create
  const stages: Array<[number, bigint, bigint, bigint]> = [
    [0, 100n, ethers.parseEther("0.0001"), 0n],
    [1, 200n, ethers.parseEther("0.0002"), 0n],
  ];

  const nftBaseURI = "ipfs://bafy.../ticket.json";
  const nftName = ""; // ignored by clone-friendly NFT (kept for signature)
  const nftSymbol = ""; // ignored by clone-friendly NFT (kept for signature)

  console.log("----------------------------------------------------");
  console.log("Creating raffle with params:");
  console.log({ durationSeconds, thresholdPercent, prizes, stages, nftBaseURI });

  // -----------------------------
  // ✅ Variant A: predict return via staticCall (no event parsing)
  // -----------------------------
  const [predictedRaffleId, predictedRaffleAddr] =
    await marketplace.createRaffle.staticCall(
      BigInt(durationSeconds),
      BigInt(thresholdPercent),
      prizes,
      stages,
      nftBaseURI,
      nftName,
      nftSymbol
    );

  console.log("Predicted:");
  console.log(" raffleId:", predictedRaffleId.toString());
  console.log(" raffleAddr:", predictedRaffleAddr);

  // -----------------------------
  // Send tx
  // -----------------------------
  const tx = await marketplace.createRaffle(
    BigInt(durationSeconds),
    BigInt(thresholdPercent),
    prizes,
    stages,
    nftBaseURI,
    nftName,
    nftSymbol
  );

  console.log("Tx hash:", tx.hash);
  await tx.wait(waitConfirmations);

  console.log("----------------------------------------------------");
  console.log("Raffle created (from staticCall prediction):");
  console.log("raffleId:", predictedRaffleId.toString());
  console.log("raffleAddress:", predictedRaffleAddr);

  // Optional write-out for frontend / ops
  const outPath = "build/raffle/LastCreatedRaffle.json";
  const abs = path.join(process.cwd(), outPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(
    abs,
    JSON.stringify(
      {
        raffleId: predictedRaffleId.toString(),
        raffleAddress: predictedRaffleAddr,
        marketplace: marketplaceAddress,
      },
      null,
      2
    ) + "\n",
    "utf8"
  );
  console.log(`Wrote ${outPath}`);
}

main().catch((e) => {
  console.error("SCRIPT ERROR:", e);
  process.exitCode = 1;
});