import {task} from 'hardhat/config';
import { 
    deployOracle,
    getOracle,
    getAddress,
    waitTx,
} from '../scripts/utils/contracts';

import { BigNumber } from 'ethers';

task('oracle:deploy', 'Deploy Oracle')
    .addFlag('verify', 'Verify contract at Etherscan')
    .addParam('operator', 'Oracle operator address')
    .setAction(async ({ verify, operator }, hre) => {
        await hre.run('set-DRE');
        const oracle = await deployOracle(operator, verify);
    });

task('oracle:addAsset', 'Add asset to oracle')
    .addParam('asset', 'Asset Symbol')
    .setAction(async ({ asset }, hre) => {
        await hre.run('set-DRE');
        const oracle = await getOracle();
        if(!oracle) throw new Error(`Oracle not found`);
        const assetAddress = await getAddress(asset);
        if(!assetAddress) throw new Error(`Asset ${asset} not found`);
        await waitTx(await oracle.addAssets([assetAddress]));
    });

task('oracle:setOperator', 'Set oracle operator')
    .addParam('operator', 'Oracle operator address')
    .setAction(async ({ operator }, hre) => {
        await hre.run('set-DRE');
        const oracle = await getOracle();
        if(!oracle) throw new Error(`Oracle not found`);
        await waitTx(await oracle.setOperator(operator));
    });

task('dev:oracle:setAssetPriceAndVolatility', 'Set asset price')
    .addParam('asset', 'Asset Symbol')
    .addParam('price', 'Asset price')
    .addParam('vol', 'Asset volatility')
    .setAction(async ({ asset, price, vol }, hre) => {
        await hre.run('set-DRE');
        const oracle = await getOracle();
        if(!oracle) throw new Error(`Oracle not found`);
        const operator = (await hre.ethers.getSigners())[2];
        if(!operator) throw new Error(`Operator not found`);
        const assetAddress = await getAddress(asset);
        if(!assetAddress) throw new Error(`Asset ${asset} not found`);
        const [outerIndex, innerIndex] = await oracle.getIndexes(assetAddress);
        await waitTx(await oracle.connect(operator).batchSetAssetPrice([outerIndex], [[{index: innerIndex, price: BigNumber.from(price), vol: BigNumber.from(vol)}]]));
    });