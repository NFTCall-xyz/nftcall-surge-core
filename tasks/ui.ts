import { task } from "hardhat/config";
import { deploySurgeUI, getAddress } from "../scripts/utils/contracts";

task("ui:deploy", "Deploy UI")
  .addFlag("verify", "Verify contract at Etherscan")
  .setAction(async ({ verify }, hre) => {
    await hre.run("set-DRE");
    const ui = await deploySurgeUI(verify);
    // const BAYC = await getAddress("BAYC");
    // const MAYC = await getAddress("MAYC");
    // const Vault = await getAddress("Vault");
    // const NFTCallOracle = await getAddress("NFTCallOracle");

    // const returnValues = await ui.getCollections(
    //   [BAYC, MAYC],
    //   NFTCallOracle,
    //   Vault
    // );

    // console.log(returnValues);
    // const returnValues2 = await ui.getCollection(BAYC, NFTCallOracle, Vault);

    // console.log(returnValues2);
  });
