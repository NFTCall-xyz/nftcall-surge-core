import { HardhatUserConfig } from "hardhat/config";
import path from 'path';
import fs from 'fs';
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const SKIP_LOAD = process.env.SKIP_LOAD === "true";

if ( !SKIP_LOAD ) {
    const tasksPath = path.join(__dirname, "tasks");
    if( fs.existsSync(tasksPath) ){
        fs.readdirSync(tasksPath)
        .filter((pth) => pth.includes(".ts"))
        .forEach((task) => {
            require(`${tasksPath}/${task}`);
        }
    );
  }
};

const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY || '';
const INFURA_KEY = process.env.INFURA_KEY || '';

const config: HardhatUserConfig = {
  typechain: {
    outDir: "types",
    target: "ethers-v5",
  },
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  mocha: {
    timeout: 20000,
  },
  defaultNetwork: "hardhat",
  networks: {
    /*localhost: {
      accounts: 'remote',
      url: 'http://127.0.0.1:8545'
    },*/
    arbitrumGoerli: {
      chainId: 421613,
      url: INFURA_KEY ? `https://goerli.infura.io/v3/${INFURA_KEY}` : `https://arb-goerli.g.alchemy.com/v2/${ALCHEMY_API_KEY}`,
      accounts: [process.env.ARB_GOERLI_PRIVATE_KEY || '', process.env.OPERATOR_PRIVATE_KEY || ''],
    }
  },
  gasReporter: {
    enabled: true,
    gasPrice: 21,
  },
  etherscan: {
    apiKey: {
      arbitrumGoerli: process.env.ETHERSCAN_KEY || '',
    }
  },
};

export default config;
