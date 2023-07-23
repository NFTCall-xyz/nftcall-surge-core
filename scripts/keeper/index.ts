import {getDb} from './db';
import {DRE} from '../utils';
import { getKeeperHelper, getAddress, getVault } from '../utils/contracts';

export const getOptionData = async (market: string, tokenId: string) => {
    const db = await getDb();
    const networkName = DRE.network.name;
}

export const activateOptions = async (market: string) => {
    const keeperHelper = await getKeeperHelper();
    const vault = await getVault();
    const nft = await getAddress(market);
    if(keeperHelper === undefined || vault === undefined) {
        throw Error('KeeperHelper is not deployed');
    }
    const positionIds = await keeperHelper.getPendingOptions(nft);
    console.log('👉 activating positionIds:', positionIds);
    if(positionIds.length > 0) {
        try {
            await keeperHelper.batchActivateOptions(nft, positionIds);
        } catch (error) {
            let failedPositions = [];
            for(const positionId of positionIds) {
                try {
                    await vault.activePosition(nft, positionId);
                }
                catch (error) {
                    failedPositions.push(positionId);
                    console.log('👉 failed to activate positionId:', positionId);
                    console.log(error);
                }
            }
        }
    }
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
    if(positionIds.length > 0) {
        await keeperHelper.batchCloseOptions(nft, positionIds);
    }
    console.log('PositionIds closed');
}

export const processMarket = async (market: string) => {
    await activateOptions(market);
    await cloesOptions(market);
}