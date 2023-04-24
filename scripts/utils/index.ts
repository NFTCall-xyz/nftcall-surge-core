import {HardhatRuntimeEnvironment} from 'hardhat/types';
import { BigNumber } from 'ethers';
const low = require('lowdb');
const FileSync = require('lowdb/adapters/FileSync');

let _baseDB: any;
let _marketDB: any;

export let DRE: HardhatRuntimeEnvironment;

export const setDRE = (_DRE: HardhatRuntimeEnvironment) => {
    DRE = _DRE;
}

export const getBaseDb = () => {
    if(_baseDB == null) {
        _baseDB = low(new FileSync('deployed-contracts-base.json'));
    }
    return _baseDB;
}

export const getMarketDb = () => {

    if(_marketDB == null) {
        _marketDB = low(new FileSync('deployed-contracts-market.json'));
    }
    return _marketDB;
}

export const getDb = (marketName?: string) => {
    if(marketName === undefined) {
        return getBaseDb();
    }
    else {
        return getMarketDb();
    }
}

export const bigNumber = (number: number, decimals: number = 0) => {
    return BigNumber.from(number).mul(BigNumber.from(10).pow(decimals));
}