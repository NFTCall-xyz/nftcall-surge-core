import { Signer } from 'ethers';

import { DRE } from '../scripts/utils';
import {
    getAddress,
    getLPToken,
    getMintableERC20,
    getOptionToken,
    getOracle,
    getPricer,
    getReserve,
    getRiskCache,
    getVault
} from '../scripts/utils/contracts';
import { 
    AssetRiskCache,
    LPToken,
    NFTCallOracle, 
    OptionPricer, 
    Vault, 
    MintableERC20, 
    OptionToken,
    Reserve
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
    oracle?: NFTCallOracle;
    pricer?: OptionPricer;
    riskCache?: AssetRiskCache;
    lpToken?: LPToken;
    dai?: MintableERC20;
    markets: {[key:string]: Market};
};

export const testEnv: TestEnv = {
    users: [],
    markets: {},
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
    testEnv.reserve = await getReserve();
    testEnv.pricer = await getPricer();
    testEnv.riskCache = await getRiskCache();
    testEnv.lpToken = await getLPToken();
    testEnv.dai = await getMintableERC20('DAI');
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
