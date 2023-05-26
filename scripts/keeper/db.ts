const low = require('lowdb');
const FileSync = require('lowdb/adapters/FileSync');

import { AsyncDatabase } from 'promised-sqlite3';
import sqlite3 from 'sqlite3';
import { BigNumber } from "ethers";
import { deployBlackScholes } from '../utils/contracts';

let _fileDB: any = null;

export const getDb = async () => {
    if(_fileDB == null) {
        _fileDB = await AsyncDatabase.open('./options.sqlite3', sqlite3.OPEN_READWRITE | sqlite3.OPEN_CREATE);
        await createDb();
    }
    return _fileDB;
}

const createDb = async () => {
    await _fileDB.run(`CREATE TABLE IF NOT EXISTS options (
        token_id CHAR(32) PRIMARY KEY,
        collection CHAR(20),
        option_type CHAR(1),
        spot_price CHAR(32),
        strike_price CHAR(32),
        amount CHAR(32),
        expiry CHAR(32)
    );`);
    await _fileDB.run(`INSERT INTO options (token_id, collection, option_type, spot_price, strike_price, amount, expiry) VALUES(?, ?, ?, ?, ?, ?, ?)`, 
        []);
}
