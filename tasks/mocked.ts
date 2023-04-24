import { task } from 'hardhat/config';
import { 
    deployMintableERC20,
    deployMintableERC721
} from '../scripts/utils/contracts';

task('mocked:erc20:deploy', 'Deploy Mocked ERC20')
    .addFlag('verify', 'Verify contract at Etherscan')
    .addParam('symbol', 'ERC20 Symbol')
    .addParam('name', 'ERC20 Name')
    .setAction(async ({ verify, symbol, name }, hre) => {
        await hre.run('set-DRE');
        const erc20 = await deployMintableERC20(name, symbol, verify);
    });

task('mocked:erc721:deploy', 'Deploy Mocked ERC721')
    .addFlag('verify', 'Verify contract at Etherscan')
    .addParam('symbol', 'ERC721 Symbol')
    .addParam('name', 'ERC721 Name')
    .setAction(async ({ verify, symbol, name }, hre) => {
        await hre.run('set-DRE');
        const erc721 = await deployMintableERC721(name, symbol, verify);
    });