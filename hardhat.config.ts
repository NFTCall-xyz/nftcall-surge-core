import { HardhatUserConfig } from "hardhat/config";
import path from 'path';
import fs from 'fs';
import "@nomicfoundation/hardhat-toolbox";


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
  networks: {
    localhost: {
      accounts: 'remote',
      url: 'http://127.0.0.1:8545'
    },
  },
};

export default config;
