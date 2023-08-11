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
    deployKeeperHelper,
    initializeLPToken,
    initializeOptionToken,
    initializeMarket,
    deployBackstopPool
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
    const erc20 = await deployMintableERC20("Mocked WETH", "WETH", bigNumber(1000000, 18).toString());
    const nft = await deployMintableERC721("Mocked BAYC", "BAYC");
    const oracle = await deployOracle(await operator.getAddress());
    const lpToken = await deployLPToken(erc20.address, 'NFTCall ETH', 'ncETH');
    await erc20.setWhitelistAddress(lpToken.address, true);
    await erc20.mint();
    await deployBlackScholes();
    const pricer = await deployPricer();
    const riskCache = await deployRiskCache();
    const reserve = await deployReserve();
    const backstopPool = await deployBackstopPool();
    const vault = await deployVault(erc20.address, lpToken.address, oracle.address, pricer.address, riskCache.address, reserve.address, backstopPool.address);
    await erc20.setWhitelistAddress(vault.address, true);
    await riskCache.transferOwnership(vault.address);
    await initializeLPToken(bigNumber(1000000, 18));
    const optionToken = await deployOptionToken(nft.address, "NFTCall BAYC Options Token", "ncBAYC", "https://bayc.finance/", "BAYC");
    await oracle.addAssets([nft.address]);
    await oracle.setOperator(operator.address);
    const [outerIndex, innerIndex] = await oracle.getIndexes(nft.address);
    await oracle.connect(operator).batchSetAssetPrice([outerIndex], [[{index: innerIndex, price: bigNumber(100, 2), vol: bigNumber(5, 2)}]]);
    await pricer.initialize(vault.address, riskCache.address, oracle.address);
    await initializeOptionToken('BAYC');
    await initializeMarket('BAYC', bigNumber(50, 6-2));
    const keeperHelper = await deployKeeperHelper(vault.address);
    await vault.setKeeper(keeperHelper.address);
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
