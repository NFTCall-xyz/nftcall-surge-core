import RawBRE from 'hardhat';
import { DRE, bigNumber } from '../scripts/utils';
import { 
    deployLPToken,
    deployMintableERC20,
    deployMintableERC721,
    deployOptionToken,
    deployOracle,
    deployPricer,
    deployReserve,
    deployRiskCache,
    deployVault,
    deployBlackScholes,
    initializeLPToken,
    initializeOptionToken,
    initializeMarket
} from '../scripts/utils/contracts';
import {
    initializeMakeSuite,
} from './make-suite';


async function buildTestEnv() {
    const contracts = await import('../scripts/utils/contracts');
    console.time('setup');
    const accounts = await DRE.ethers.getSigners();

    // oracle
    const [ _, owner, operator, ...a] = accounts;
    const erc20 = await deployMintableERC20("Mocked Dai", "DAI");
    const nft = await deployMintableERC721("Mocked BAYC", "BAYC");
    const oracle = await deployOracle(await operator.getAddress());
    const lpToken = await deployLPToken(erc20.address);
    await deployBlackScholes();
    const pricer = await deployPricer();
    const riskCache = await deployRiskCache();
    const reserve = await deployReserve();
    const vault = await deployVault(erc20.address, lpToken.address, oracle.address, pricer.address, riskCache.address, reserve.address);
    await initializeLPToken(bigNumber(1000000, 18));
    const optionToken = await deployOptionToken(nft.address, "NFTSurge BAYC option", "optionBAYC", "https://bayc.finance/", "BAYC");
    await oracle.addAssets([nft.address]);
    await oracle.setOperator(operator.address);
    const [outerIndex, innerIndex] = await oracle.getIndexes(nft.address);
    await oracle.connect(operator).batchSetAssetPrice([outerIndex], [[{index: innerIndex, price: bigNumber(100, 2), vol: bigNumber(5, 2)}]]);
    await pricer.initialize(riskCache.address, oracle.address);
    await initializeOptionToken('BAYC');
    await initializeMarket('BAYC', bigNumber(50, 6-2));
    
    console.timeEnd('setup');
}

before(async () => {
    await RawBRE.run('set-DRE');
    await buildTestEnv();
    await initializeMakeSuite();
    console.log('\n***************');
    console.log('Setup and snapshot finished');
    console.log('***************\n');
});
