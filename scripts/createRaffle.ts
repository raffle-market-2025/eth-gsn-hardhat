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
  if (b.length !== 2) throw new Error("country2 must be exactly 2 ASCII chars (ISO-3166-1 alpha-2)");
  // ethers v6 FixedBytesCoder требует ровно 2 байта
  return ethers.hexlify(b); // e.g. "UA" -> "0x5541"
}

async function main() {
  const { ethers } = await network.connect();

  // ✅ New style: take network from provider (ethers v6) and assert chainId
  const net = await ethers.provider.getNetwork();
  const isDev =
    developmentChains.includes(net.name as any) ||
    net.chainId === 31337n ||
    net.chainId === 1337n;

  if (!isDev && net.chainId !== 11155111n) {
    throw new Error(`Expected Sepolia chainId=11155111, got ${net.chainId.toString()}`);
  }

  const cfg = !isDev ? networkConfig[11155111] : undefined;
  void cfg;

  const waitConfirmations = 2;

  const [deployer] = await ethers.getSigners();
  const deployerAddr = await deployer.getAddress();

  console.log("----------------------------------------------------");
  console.log(`Network: ${net.name} (chainId=${net.chainId.toString()})`);
  console.log(`Deployer: ${deployerAddr}`);

  const marketplaceAddress =
    process.env.MARKETPLACE_ADDRESS ?? readAddressJson("build/raffle/RaffleMarketplace.json");
  console.log("Marketplace:", marketplaceAddress);

  // Addresses (optional; used for optional auto-wiring)
  const verifierAddress =
    process.env.VERIFIER_ADDRESS ?? (() => {
      try { return readAddressJson("build/raffle/Verifier.json"); } catch { return ""; }
    })();

  const automationAddress =
    process.env.AUTOMATION_ADDRESS ?? (() => {
      try { return readAddressJson("build/raffle/RaffleAutomationVRF.json"); } catch { return ""; }
    })();

  const nftImplAddress =
    process.env.RAFFLE_NFT_IMPL_ADDRESS ?? (() => {
      // подстройте под ваш путь, если пишете файл иначе
      try { return readAddressJson("build/raffle/RaffleNFTImplementation.json"); } catch { return ""; }
    })();

  // Marketplace ABI: createRaffle + infra getters/setters + event
  const MARKET_ABI = [
    // getters (public vars or explicit getters)
    "function verifier() view returns (address)",
    "function automation() view returns (address)",
    "function raffleNftImplementation() view returns (address)",

    // setters (onlyOwner)
    "function setVerifier(address) external",
    "function setAutomation(address) external",
    "function setRaffleNftImplementation(address) external",

    // create
    "function createRaffle(uint256,uint256,(string,bytes2,uint256)[],(uint8,uint256,uint256,uint256)[],string,string,string) returns (uint256,address)",

    "event RaffleCreated(uint256 indexed raffleId,address indexed raffleAddress,address indexed raffleOwner)",
  ] as const;

  const marketplace = new ethers.Contract(marketplaceAddress, MARKET_ABI, deployer);

  // -----------------------------
  // Preflight: check wiring
  // -----------------------------
  const curVerifier: string = await marketplace.verifier();
  const curAutomation: string = await marketplace.automation();
  const curNftImpl: string = await marketplace.raffleNftImplementation();

  const Z = "0x0000000000000000000000000000000000000000";
  console.log("Wiring:");
  console.log(" verifier:", curVerifier);
  console.log(" automation:", curAutomation);
  console.log(" raffleNftImplementation:", curNftImpl);

  // Если вы хотите, чтобы скрипт сам подставлял (когда деплойер = owner),
  // раскомментируйте блок ниже. И обеспечьте наличие адресов через build/env.
  /*
  if (curVerifier === Z && verifierAddress) {
    console.log("Setting verifier...");
    const tx = await marketplace.setVerifier(verifierAddress);
    console.log(" tx:", tx.hash);
    await tx.wait(waitConfirmations);
  }

  if (curAutomation === Z && automationAddress) {
    console.log("Setting automation...");
    const tx = await marketplace.setAutomation(automationAddress);
    console.log(" tx:", tx.hash);
    await tx.wait(waitConfirmations);
  }

  if (curNftImpl === Z && nftImplAddress) {
    console.log("Setting raffleNftImplementation...");
    const tx = await marketplace.setRaffleNftImplementation(nftImplAddress);
    console.log(" tx:", tx.hash);
    await tx.wait(waitConfirmations);
  }
  */

  // Минимально-строго: если nftImpl не задан — объясняем и выходим
  const curNftImpl2: string = await marketplace.raffleNftImplementation();
  if (curNftImpl2 === Z) {
    throw new Error(
      "Marketplace__NftImplNotSet(): в RaffleMarketplace не задан raffleNftImplementation.\n" +
      "Нужно один раз вызвать setRaffleNftImplementation(<RaffleNFT implementation address>) от owner marketplace.\n" +
      "Проще всего добавить это в infra-deploy скрипт."
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
  const nftName = "";   // ignored by clone-friendly NFT (kept for signature)
  const nftSymbol = ""; // ignored by clone-friendly NFT (kept for signature)

  console.log("----------------------------------------------------");
  console.log("Creating raffle with params:");
  console.log({ durationSeconds, thresholdPercent, prizes, stages, nftBaseURI });

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
  const receipt = await tx.wait(waitConfirmations);

  // -----------------------------
  // Parse RaffleCreated
  // -----------------------------
  let raffleId: bigint | null = null;
  let raffleAddr: string | null = null;

  for (const log of receipt.logs) {
    try {
      const parsed = marketplace.interface.parseLog(log);
      if (parsed?.name === "RaffleCreated") {
        raffleId = parsed.args.raffleId as bigint;
        raffleAddr = parsed.args.raffleAddress as string;
        break;
      }
    } catch {
      // ignore
    }
  }

  if (!raffleId || !raffleAddr) {
    throw new Error("RaffleCreated event not found. Check ABI/events.");
  }

  console.log("----------------------------------------------------");
  console.log("Raffle created:");
  console.log("raffleId:", raffleId.toString());
  console.log("raffleAddress:", raffleAddr);

  const outPath = "build/raffle/LastCreatedRaffle.json";
  const abs = path.join(process.cwd(), outPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(
    abs,
    JSON.stringify(
      { raffleId: raffleId.toString(), raffleAddress: raffleAddr, marketplace: marketplaceAddress },
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