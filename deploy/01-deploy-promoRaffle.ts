import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { network } from "hardhat";

//import { developmentChains } from "../helper-hardhat-config";
// import verify from "../utils/verify";
// import pause from "../utils/pause";

// JSON с адресом форвардера (resolveJsonModule в tsconfig)
import forwarderJson from "../build/gsn/Forwarder.json";

const func: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const forwarderAddress = (forwarderJson as any).address;

  const args = [1, forwarderAddress, deployer];
  console.log("PromoRaffle args:", args);

  const promoRaffle = await deploy("PromoRaffle", {
    from: deployer,
    args,
    log: true,
  });

  // при желании — пауза и верификация
  // await pause(120000);
  // if (!developmentChains.includes(network.name)) {
  //   console.log("Verifying PromoRaffle ....");
  //   await verify(promoRaffle.address, args);
  // }

  const baseTokenURI =
    "ipfs://bafybeidh6xhjihvmkha6yuxyjol7ubccdmvx6i3m6vdc6pawkykjlcx2ju/promo.json";

  const argsNFT = [baseTokenURI, promoRaffle.address];

  const promoRaffleNFT = await deploy("PromoNFT", {
    from: deployer,
    args: argsNFT,
    log: true,
  });

  console.log(
    `NFT Storage for PromoRaffle smart contract deployed to ${promoRaffleNFT.address}`
  );

  // await pause(120000);
  // if (!developmentChains.includes(network.name)) {
  //   console.log("Verifying promoRaffleNFT storage ....");
  //   await verify(promoRaffleNFT.address, argsNFT);
  // }

  log("----- PromoRaffle deployed ---------------------------------------");
};

func.tags = ["all", "promoRaffle"];

export default func;
