import {getDb} from './db';
import {DRE} from '../utils';
import { getKeeperHelper, getAddress, getVault, waitTx, getRiskCache, getOptionToken } from '../utils/contracts';
import { bigNumber, getMarkets } from '../utils';
import { BigNumber } from 'ethers';

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
            await waitTx(await keeperHelper.batchActivateOptions(nft, positionIds));
        } catch (error) {
            let failedPositions = [];
            for(const positionId of positionIds) {
                try {
                    await waitTx(await vault.activePosition(nft, positionId));
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
        await waitTx(await keeperHelper.batchCloseOptions(nft, positionIds));
    }
    console.log('PositionIds closed');
}

export const updateRisk = async (market: string) => {
    const keeperHelper = await getKeeperHelper();
    const nft = await getAddress(market);
    if(keeperHelper === undefined) {
        throw Error('KeeperHelper is not deployed');
    }
    const riskCache = await getRiskCache();
    if(riskCache === undefined) {
        throw Error('RiskCache is not deployed');
    }
    let oldPNL = BigNumber.from(0);
    let oldDelta = BigNumber.from(0);
    const oldRisk = await riskCache.getAssetRisk(nft);
    oldPNL = oldRisk.PNL;
    oldDelta = oldRisk.delta;
    let newPNL = BigNumber.from(0);
    let newDelta = BigNumber.from(0);
    const positionIds = await keeperHelper.getActiveOptions(nft);
    console.log('👉 updated delta and PNL of positionIds:', positionIds);
    if(positionIds.length > 0) {
        const optionToken = await getOptionToken(market);
        if(optionToken === undefined) {
            throw Error('OptionToken is not deployed');
        }
        const risk = await keeperHelper.sumPNLWeightedDelta(nft, positionIds);
        newPNL = risk.PNL;
        newDelta = risk.weightedDelta.mul(bigNumber(1, 18)).div(await optionToken.totalAmount());
    }
    if((!oldPNL.eq(newPNL)) || (!oldDelta.eq(newDelta))) {
        await waitTx(await keeperHelper.updateCollectionRisk(nft, newPNL, newDelta));
        console.log('Updated delta and PNL');
        return true;
    }
    else {
        console.log('No need to update delta and PNL');
        return false;
    }
}

export const processMarket = async (market: string) => {
    await cloesOptions(market);
    const needToUpdatePNL = await updateRisk(market);
    await activateOptions(market);
    return needToUpdatePNL;
}

export const updatePNL = async () => {
    const vault = await getVault();
    if(vault === undefined) {
        throw Error('Vault is not deployed');
    }
    await waitTx(await vault.updateUnrealizedPNL());
}

export const processAllMarkets = async () => {
    const markets = await getMarkets();
    let needToUpdatePNL = false;
    for(let market of markets){
        needToUpdatePNL ||= await processMarket(market);
    }
    if(needToUpdatePNL) {
        await updatePNL();
    }
}