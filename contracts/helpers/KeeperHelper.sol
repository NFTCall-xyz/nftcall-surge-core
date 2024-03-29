// SPDX-license-identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault, Strike} from "../interfaces/IVault.sol";
import {OptionPosition, PositionState} from "../interfaces/IOptionToken.sol";
import {OptionToken} from "../tokens/OptionToken.sol";

contract KeeperHelper is Ownable{
    address private _vault;

    constructor(address vault_) Ownable(){
        _vault = vault_;
    }

    function getPendingOptions(address collection) external view returns (uint256[] memory tokenIds) {
        OptionToken optionToken = OptionToken(IVault(_vault).marketConfiguration(collection).optionToken);
        uint256 totalPendingTokens = 0;
        for(uint256 i = 0; i < optionToken.totalSupply(); ++i){
            if(optionToken.optionPositionState(optionToken.tokenByIndex(i)) == PositionState.PENDING){
                ++totalPendingTokens;
            }
        }
        tokenIds = new uint256[](totalPendingTokens);
        uint256 index = 0;
        uint256 resultIndex = 0;
        while(resultIndex < totalPendingTokens) {
            uint256 tokenId = optionToken.tokenByIndex(index);
            if(optionToken.optionPositionState(tokenId) == PositionState.PENDING){
                tokenIds[resultIndex] = tokenId;
                ++resultIndex;
            }
            ++index;
        }
        return tokenIds;
    }

    function getExpiredOptions(address collection) external view returns (uint256[] memory tokenIds) {
        OptionToken optionToken = OptionToken(IVault(_vault).marketConfiguration(collection).optionToken);
        uint256 totalExpiredTokens = 0;
        uint256 currentTime = block.timestamp;
        for(uint256 i = 0; i < optionToken.totalSupply(); ++i){
            uint256 tokenId = optionToken.tokenByIndex(i);
            OptionPosition memory position = optionToken.optionPosition(tokenId);
            if(position.state == PositionState.ACTIVE && IVault(_vault).strike(position.strikeId).expiry <= currentTime){
                ++totalExpiredTokens;
            }
        }
        tokenIds = new uint256[](totalExpiredTokens);
        uint256 index = 0;
        uint256 resultIndex = 0;
        while(resultIndex < totalExpiredTokens){
            uint256 tokenId = optionToken.tokenByIndex(index);
            OptionPosition memory position = optionToken.optionPosition(tokenId);
            if(position.state == PositionState.ACTIVE && IVault(_vault).strike(position.strikeId).expiry <= currentTime){
                tokenIds[resultIndex] = tokenId;
                ++resultIndex;
            }
            ++index;
        }
        return tokenIds;
    }

    function getActiveOptions(address collection) external view returns (uint256[] memory tokenIds) {
        OptionToken optionToken = OptionToken(IVault(_vault).marketConfiguration(collection).optionToken);
        uint256 totalActiveTokens = 0;
        uint256 currentTime = block.timestamp;
        for(uint256 i = 0; i < optionToken.totalSupply(); ++i){
            uint256 tokenId = optionToken.tokenByIndex(i);
            OptionPosition memory position = optionToken.optionPosition(tokenId);
            if(position.state == PositionState.ACTIVE && IVault(_vault).strike(position.strikeId).expiry > currentTime){
                ++totalActiveTokens;
            }
        }
        tokenIds = new uint256[](totalActiveTokens);
        uint256 index = 0;
        uint256 resultIndex = 0;
        while(resultIndex < totalActiveTokens){
            uint256 tokenId = optionToken.tokenByIndex(index);
            OptionPosition memory position = optionToken.optionPosition(tokenId);
            if(position.state == PositionState.ACTIVE && IVault(_vault).strike(position.strikeId).expiry > currentTime){
                tokenIds[resultIndex] = tokenId;
                ++resultIndex;
            }
            ++index;
        }
        return tokenIds;
    }

    function getOptionData(address collection, uint256[] calldata positionIds) external view returns (OptionPosition[] memory optionPositions, Strike[] memory strikes) {
        optionPositions = new OptionPosition[](positionIds.length);
        strikes = new Strike[](positionIds.length);
        OptionToken optionToken = OptionToken(IVault(_vault).marketConfiguration(collection).optionToken);
        for(uint256 i = 0; i < positionIds.length; ++i){
            optionPositions[i] = optionToken.optionPosition(positionIds[i]);
            strikes[i] = IVault(_vault).strike(optionPositions[i].strikeId);
        }
        return (optionPositions, strikes);
    }

    function batchActivateOptions(address collection, uint256[] calldata positionIds) external onlyOwner{
        IVault vault_ = IVault(_vault);
        for(uint256 i = 0; i < positionIds.length; ++i){
            uint256 positionId = positionIds[i];
            vault_.activatePosition(collection, positionId);
        }
    }

    function batchCloseOptions(address collection, uint256[] calldata positionIds) external onlyOwner{
        IVault vault_ = IVault(_vault);
        for(uint256 i = 0; i < positionIds.length; ++i){
            uint256 positionId = positionIds[i];
            vault_.closePosition(collection, positionId);
        }
    }

    function batchForceClosePendingPositions(address collection, uint256[] calldata positionIds) external onlyOwner {
        IVault vault_ = IVault(_vault);
        for(uint256 i = 0; i < positionIds.length; ++i){
            uint256 positionId = positionIds[i];
            vault_.forceClosePendingPosition(collection, positionId);
        }
    }

    function sumPNLWeightedDelta(address collection, uint256[] calldata positionIds) external view returns(int256 PNL, int256 weightedDelta) {
        IVault vault_ = IVault(_vault);
        for(uint256 i = 0; i < positionIds.length; ++i){
            uint256 positionId = positionIds[i];
            (int256 pPNL, int256 pDelta) = vault_.positionPNLWeightedDelta(collection, positionId);
            PNL -= pPNL;
            weightedDelta -= pDelta;
        }
    }

    function updateCollectionRisk(address collection, int256 delta, int256 PNL) external onlyOwner {
        IVault vault_ = IVault(_vault);
        vault_.updateCollectionRisk(collection, delta, PNL);
    }
}