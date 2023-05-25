import { BigNumber, ContractTransaction } from 'ethers';
import { DRE, bigNumber, getDb } from './';
import { 
    ERC20,
    ERC721,
    Vault, 
    LPToken,
    OptionToken,
    OptionPricer,
    NFTCallOracle,
    AssetRiskCache,
    Reserve,
    MintableERC20,
    MintableERC721,
    BlackScholes,
    KeeperHelper,
} from '../../types';

function getKey(name: string, marketName?: string) {
    if( marketName === undefined) {
        return `${name}.${DRE.network.name}.address`;
    }
    else {
        return `${name}.${DRE.network.name}.${marketName}`;
    }
}

export const getAddress = async (name: string, marketName?: string) => {
    return (await getDb(marketName).get(getKey(name, marketName))).value();
}

export const saveAddress = async (name: string, address: string, marketName?: string) => {
    await getDb(marketName)
          .set(getKey(name, marketName), address)
          .write();
}

export const waitTx = async (tx: ContractTransaction) => {
    console.log('🍵 TransactionHash:', tx.hash);
    const res = await tx.wait(1);
    console.log('✅ gasUsed', res.gasUsed.toString());
    return res;
}

export const getSigner = async (index: number = 0) => {
    const accounts = await DRE.ethers.getSigners();
    return accounts[index];
}

export const getContract = async<T>(contractName: string, dbName?: string, address?: string, marketName?: string) => {
    const name = dbName ?? contractName;
    const addr = address ?? await getAddress(name, marketName);
    if(!addr) {
        return undefined;
    }
    console.log(`Get ${contractName} Contract at ${addr}`);
    return (await DRE.ethers.getContractAt(contractName, addr)) as T;
}

export const getTxConfig = () => {
    let txConfig = {}
    if (process.env.maxPriorityFeePerGas && process.env.maxFeePerGas && process.env.gasLimit) {
        txConfig = {
            maxPriorityFeePerGas: process.env.maxPriorityFeePerGas,
            maxFeePerGas: process.env.maxFeePerGas,
            gasLimit: process.env.gasLimit,
        }
        console.log('👉 Get Config:', txConfig);
    };
    return txConfig;
}

export const deployContract = async<T> (contractName: string, args: any[], dbName?: string, marketName?: string, libraries?: {[key: string]: string}) => {
    const name = dbName ?? contractName;
    console.log(`Deploying ${name} contract...`);
    const contractFactory = (libraries === undefined)
                                ? await DRE.ethers.getContractFactory(contractName)
                                : await DRE.ethers.getContractFactory(contractName, {libraries: libraries});
    const txConfig = getTxConfig();
    const contract = await contractFactory.deploy(...args, txConfig);
    await contract.deployed();
    console.log(`✅  Deployed ${name} contract at ${contract.address}`);
    
    await saveAddress(name, contract.address, marketName);
    return contract as T;
}

export const deployLPToken = async (erc20Asset: string, name: string, symbol: string, verify: boolean = false) => {
    console.log(`Deploying LPToken contract for ${erc20Asset}...`);
    const lpToken = await deployContract<LPToken>('LPToken', [erc20Asset, name, symbol]);
    return lpToken;
}

export const deployOracle = async (operator: string, verify: boolean = false) => {
    const oracle = await deployContract<NFTCallOracle>('NFTCallOracle', [operator, []]);
    return oracle;
}

export const deployPricer = async (verify: boolean = false) => {
    const blackScholesAddress = await getAddress('BlackScholes');
    console.log(`got BlackScholes library at: ${blackScholesAddress}`);
    if(blackScholesAddress === undefined){
        throw Error('Please deploy the blackscholes library first');
    }
    const libraries = {
        ["contracts/libraries/BlackScholes.sol:BlackScholes"]: blackScholesAddress,
    };
    const pricer = await deployContract<OptionPricer>('OptionPricer', [], undefined, undefined, libraries);
    return pricer;
}

export const deployRiskCache = async (verify: boolean = false) => {
    const riskCache = await deployContract<AssetRiskCache>('AssetRiskCache', []);
    return riskCache;
}

export const deployOptionToken = async (nftAddress: string, name: string, symbol: string, baseURI: string, marketName: string, verify: boolean = false) => {
    const optionToken = await deployContract<OptionToken>('OptionToken', [nftAddress, name, symbol, baseURI], undefined, marketName);
    return optionToken;
}

export const deployVault = async (asset: string, lpToken: string, oracle: string, pricer: string, riskCache: string, reserve: string, verify: boolean = false) => {
    
    const vault = await deployContract<Vault>('Vault', [asset, lpToken, oracle, pricer, riskCache, reserve]);
    return vault;
}

export const deployReserve = async (verify: boolean = false) => {
    const reserve = await deployContract<Reserve>('Reserve', []);
    return reserve;
}

export const deployMintableERC20 = async (name: string, symbol: string, verify: boolean = false) => {
    const erc20 = await deployContract<MintableERC20>('MintableERC20', [name, symbol], symbol);
    return erc20;
}

export const deployMintableERC721 = async (name: string, symbol: string, verify: boolean = false) => {
    const erc721 = await deployContract<MintableERC721>('MintableERC721', [name, symbol], symbol);
    return erc721;
}

export const deployBlackScholes = async (verify: boolean = false) => {
    const blackScholes = await deployContract<BlackScholes>('BlackScholes', []);
    return blackScholes;
}

export const deployKeeperHelper = async (vault: string, verify: boolean = false) => {
    const keeperHelper = await deployContract<KeeperHelper>('KeeperHelper', [vault]);
    return keeperHelper;
}

export const getVault = async () => {
    return await getContract<Vault>('Vault');
}

export const getOptionToken = async (marketName: string) => {
    return await getContract<OptionToken>('OptionToken', undefined, undefined, marketName);
}

export const getLPToken = async () => {
    return await getContract<LPToken>('LPToken');
}

export const getOracle = async () => {
    return await getContract<NFTCallOracle>('NFTCallOracle');
}

export const getPricer = async () => {
    return await getContract<OptionPricer>('OptionPricer');
}

export const getRiskCache = async () => {
    return await getContract<AssetRiskCache>('AssetRiskCache');
}

export const getReserve = async() => {
    return await getContract<Reserve>('Reserve');
}

export const getMintableERC20 = async (symbol: string) => {
    return await getContract<MintableERC20>('MintableERC20', symbol);
}

export const getERC20 = async (symbol: string) => {
    return await getContract<ERC20>('ERC20', symbol);
}

export const getERC721 = async (symbol: string) => {
    return await getContract<ERC721>('ERC721', symbol);
}

export const getMintableERC721 = async (symbol: string) => {
    return await getContract<MintableERC721>('MintableERC721', symbol);
}

export const getBlackScholes = async() => {
    return await getContract<BlackScholes>('BlackScholes');
}

export const getKeeperHelper = async() => {
    return await getContract<KeeperHelper>('KeeperHelper');
}

export const initializeLPToken = async(maximumTotalAssets: BigNumber) => {
    const lpToken = await getLPToken();
    if(lpToken === undefined){
        throw Error('LPToken is not deployed');
    }
    const vault = await getVault();
    if(vault === undefined) {
        throw Error('Vault is not deployed');
    }
    await waitTx(await lpToken.initialize(vault.address, maximumTotalAssets));
}

export const initializeOptionToken = async(marketName: string) => {
    const optionToken = await getOptionToken(marketName);
    if(optionToken === undefined){
        throw Error(`OptionToken for ${marketName} is not deployed`);
    }
    const vault = await getVault();
    if(vault === undefined) {
        throw Error('Vault is not deployed');
    }
    await waitTx(await optionToken.initialize(vault.address));
}

export const initializeMarket = async(marketName: string, weight: BigNumber) => {
    const vault = await getVault();
    if(vault == undefined) {
        throw Error('Vault is not depolyed');
    }
    const nftAddress = await getAddress(marketName);
    if(nftAddress === undefined){
        throw Error(`Can not get the nft address for ${marketName}`);
    }
    const optionTokenAddress = await getAddress('OptionToken', marketName);
    if(optionTokenAddress === undefined) {
        throw Error(`The OptionToken for ${marketName} is not deployed`);
    }
    await waitTx(await vault.addMarket(nftAddress, weight, optionTokenAddress));
}