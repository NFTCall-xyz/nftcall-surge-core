import {getDb} from './db';
import {DRE} from '../utils';
import { getKeeperHelper, getAddress } from '../utils/contracts';

export const getOptionData = async (market: string, tokenId: string) => {
    const db = await getDb();
    const networkName = DRE.network.name;
}

export const activateOptions = async (market: string) => {
    const keeperHelper = await getKeeperHelper();
    const nft = await getAddress(market);
    if(keeperHelper === undefined) {
        throw Error('KeeperHelper is not deployed');
    }
    const positionIds = await keeperHelper.getPendingOptions(nft);
    console.log('👉 activating positionIds:', positionIds);
    await keeperHelper.batchActivateOptions(nft, positionIds);
    console.log('PositionIds activated');
}

export const cloesOptions = async (market: string) => {
    const keeperHelper = await getKeeperHelper();
    const nft = await getAddress(market);
    if(keeperHelper === undefined) {
        throw Error('KeeperHelper is not deployed');
    }
    const positionIds = await keeperHelper.getExpiredOptions(nft);
    console.log('👉 closing positionIds:', positionIds);
    await keeperHelper.batchCloseOptions(nft, positionIds);
    console.log('PositionIds closed');
}

export const processMarket = async (market: string) => {
    await activateOptions(market);
    await cloesOptions(market);
}