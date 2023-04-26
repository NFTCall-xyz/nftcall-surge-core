import { task } from 'hardhat/config';
import { 
    deployOptionToken,
    getAddress,
    initializeOptionToken,
} from '../scripts/utils/contracts';

task('optionToken:deploy', 'Deploy OptionToken')
    .addFlag('verify', 'Verify contract at Etherscan')
    .addParam('nftSymbol', 'NFT Symbol')
    .addParam('nftName', 'NFT Name')
    .addParam('baseURI', 'Base URI')
    .addParam('market', 'Market Name')
    .setAction(async ({ verify, nftSymbol, nftName, baseURI, market }, hre) => {
        await hre.run('set-DRE');
        const nftAddress = await getAddress(nftSymbol);
        const optionToken = await deployOptionToken(
            nftAddress, `NFTSurge ${nftSymbol} Options Token`, `nc${nftSymbol}`, baseURI, market, verify);
    });

task('optionToken:init', 'Initialize OptionToken')
    .addParam('market', 'Market Name')
    .setAction(async ({ market }, hre) => {
        await hre.run('set-DRE');
        await initializeOptionToken(market);
    });