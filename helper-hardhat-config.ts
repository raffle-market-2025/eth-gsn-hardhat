export const developmentChains = ["localhost", "hardhat"] as const;

export type SupportedChainId = 11155111; // Sepolia

export type NetworkConfigItem = {
  name: string;

  // Chainlink VRF v2.5 (V2Plus)
  vrfCoordinatorV2Plus: `0x${string}`;
  vrfKeyHash: `0x${string}`;

  // LINK token (Sepolia)
  linkToken: `0x${string}`;

  // Chainlink Automation registrar (Sepolia)
  automationRegistrar: `0x${string}`;

  // Knobs
  vrfCallbackGasLimit: number;
  automationMaxBatch: number;
  automationMaxScan: number;
};

export const networkConfig: Record<SupportedChainId, NetworkConfigItem> = {
  11155111: {
    name: "sepolia",

    // Chainlink VRF v2.5 Coordinator (Sepolia)
    vrfCoordinatorV2Plus: "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B",

    // keyHash (Sepolia)
    vrfKeyHash:
      "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae",

    // LINK token (Sepolia)
    linkToken: "0x779877A7B0D9E8603169DdbD7836e478b4624789",

    // Automation Registrar (Sepolia)
    automationRegistrar: "0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976",

    // Defaults (подберите под себя)
    vrfCallbackGasLimit: 900_000,
    automationMaxBatch: 5,
    automationMaxScan: 60,
  },
};