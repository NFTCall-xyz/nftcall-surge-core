import { task } from 'hardhat/config';
import { saveAddress, getAddress } from '../scripts/utils/contracts';
import { DRE, bigNumber } from '../scripts/utils';

task('dev:full', 'Deploy all contracts')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        const lpAsset = 'WETH';
        const markets = {
            'BAYC': {
                name: 'BAYC',
                weight: bigNumber(50, 6-2),
                baseURI: 'https://nftsurge.com/api/bayc/',
                price: bigNumber(100, 2),  // 100
                volatility: bigNumber(5, 2), // 5%
            },
            'MAYC': {
                name: 'MAYC',
                weight: bigNumber(50, 6-2),
                baseURI: 'https://nftsurge.com/api/mayc/',
                price: bigNumber(90, 2), // 90
                volatility: bigNumber(8, 2), // 8%
            },
        }
        await hre.run('set-DRE');
        const deployOnDevServer = (DRE.network.name === 'hardhat' || DRE.network.name === 'localhost');
        const accounts = await DRE.ethers.getSigners();
        console.log(`deployer address: ${await accounts[0].getAddress()}`);
        console.log(`accounts length: ${Object.keys(accounts).length}`);
        // const [, , operator, ] = accounts;
        const operator = accounts[1] || accounts[0];
        if(!operator) throw new Error(`Operator not found`);
        const operatorAddress = await operator.getAddress();
        saveAddress('operator', operatorAddress);
        await hre.run('mocked:erc20:deploy', { verify, symbol: lpAsset, name: lpAsset});
        if(DRE.network.name === 'hardhat' || DRE.network.name === 'localhost') {
            for(const [nft, market] of Object.entries(markets)) {
                await hre.run('mocked:erc721:deploy', { verify, symbol: nft, name: market.name});
            }
        }
        await hre.run('oracle:deploy', { verify, operator: operatorAddress});
        await hre.run('lpToken:deploy', { verify, underlying: lpAsset, underlyingName: "WETH" });
        await hre.run('blackScholes:deploy', { verify });
        await hre.run('pricer:deploy', { verify });
        await hre.run('riskCache:deploy', { verify });
        await hre.run('reserve:deploy', { verify });
        await hre.run('vault:deploy', { verify, asset: lpAsset });
        await hre.run('lpToken:init', { maximumSupply: '10000000' });
        await hre.run('oracle:setOperator', { operator: operatorAddress });
        for (const [nft, market] of Object.entries(markets)) {
            await hre.run('oracle:addAsset', { asset:  nft});
            await hre.run(
                'dev:oracle:setAssetPriceAndVolatility', 
                { 
                    asset: nft, 
                    price: market.price.toString(), 
                    vol: market.volatility.toString() });
        }
        await hre.run('pricer:init');
        for (const [nft, market] of Object.entries(markets)) {
            await hre.run(
                'optionToken:deploy', 
                {nftSymbol: nft, nftName: market.name, baseURI: market.baseURI, market: nft});
            console.log(`init optionToken ${nft}...`);
            await hre.run('optionToken:init', {market: nft});
            await hre.run('vault:initMarket', {market: nft, weight: market.weight.toString()});
        }
    });