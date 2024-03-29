import { BigNumber, Signer } from 'ethers';

import { DRE } from '../scripts/utils';
import {
    getAddress,
    getLPToken,
    getMintableERC20,
    getOptionToken,
    getOracle,
    getPricer,
    getReserve,
    getBackstopPool,
    getRiskCache,
    getVault,
    getKeeperHelper,
} from '../scripts/utils/contracts';
import { 
    AssetRiskCache,
    KeeperHelper,
    LPToken,
    NFTCallOracle, 
    OptionPricer, 
    Vault, 
    MintableERC20, 
    OptionToken,
    Reserve,
    BackstopPool
} from '../types';

let buidlerevmSnapshotId = '0x1';

export interface SignerWithAddress {
    signer: Signer;
    address: string;
};

export interface Market {
    nft: string;
    optionToken: OptionToken;
}

export interface TestEnv {
    deployer?: SignerWithAddress;
    users: SignerWithAddress[];
    vault?: Vault;
    reserve?: Reserve;
    backstopPool?: BackstopPool;
    oracle?: NFTCallOracle;
    pricer?: OptionPricer;
    riskCache?: AssetRiskCache;
    lpToken?: LPToken;
    keeperHelper?: KeeperHelper;
    eth?: MintableERC20;
    timeScale: BigNumber;
    markets: {[key:string]: Market};
};

export const testEnv: TestEnv = {
    users: [],
    markets: {},
    timeScale: BigNumber.from(1),
} as TestEnv;


export const initializeMakeSuite = async () => {
    console.log('initializeMakeSuite');
    const [_deployer, ...restSigners] = await DRE.ethers.getSigners();
    let users = [];
    for (const signer of restSigners) {
        users.push({
            signer, 
            address: await signer.getAddress()});
    };

    testEnv.users = users;
    testEnv.deployer = {
        signer: _deployer, 
        address: await _deployer.getAddress()
    };
    testEnv.oracle = await getOracle();
    testEnv.vault = await getVault();
    if(testEnv.vault === undefined) throw new Error(`Vault not found`);
    testEnv.timeScale = await testEnv.vault.TIME_SCALE();
    testEnv.reserve = await getReserve();
    testEnv.backstopPool = await getBackstopPool();
    testEnv.pricer = await getPricer();
    testEnv.riskCache = await getRiskCache();
    testEnv.lpToken = await getLPToken();
    testEnv.keeperHelper = await getKeeperHelper();
    testEnv.eth = await getMintableERC20('WETH');
    const baycAddress = await getAddress('BAYC');
    const baycOption = await getOptionToken('BAYC');
    if(baycAddress !== undefined && baycOption !== undefined) {
        testEnv.markets['BAYC'] = { nft: baycAddress, optionToken: baycOption};
    }
};


export function makeSuite(testName: string, tests: (testEnv: TestEnv) => void) {
    describe(testName, () => {
        before(async () => {
            const id = await DRE.ethers.provider.send('evm_snapshot', []);
            buidlerevmSnapshotId = id;
        });
        tests(testEnv);
        after(async () => {
            await DRE.ethers.provider.send('evm_revert', [buidlerevmSnapshotId]);
        });
    });
};
