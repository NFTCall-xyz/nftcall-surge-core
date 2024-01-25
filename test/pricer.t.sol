pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {MintableERC20} from "../contracts/mocked/MintableERC20.sol";
import {LPToken} from "../contracts/tokens/LPToken.sol";
import {OptionToken} from "../contracts/tokens/OptionToken.sol";
import {NFTCallOracle} from "../contracts/NFTCallOracle.sol";
import {OptionPricer} from "../contracts/OptionPricer.sol";
import {AssetRiskCache} from "../contracts/AssetRiskCache.sol";
import {Vault} from "../contracts/vault/Vault.sol";
import {ILPToken} from "../contracts/interfaces/ILPToken.sol";
import {UNIT, GENERAL_UNIT} from "../contracts/libraries/DataTypes.sol";
import {OptionType} from "../contracts/interfaces/IOptionToken.sol";


contract PricerTest is Test {
    MintableERC20 weth;
    LPToken lpToken;
    OptionToken optionToken;
    NFTCallOracle oracle;
    OptionPricer pricer;
    AssetRiskCache riskCache;
    Vault vault;
    address reserve;
    address backstopPool;
    address[] nfts;

    uint256 maximumVaultBalance = 1000 ether;

    function setUp() public {
        weth = new MintableERC20("WETH", "WETH", 100 ether);
        lpToken = new LPToken(address(weth), "lpToken", "lpToken");
        nfts = new address[](1);
        nfts[0] = address(0xED5AF388653567Af2F388E6224dC7C4b3241C544);
        oracle = new NFTCallOracle(address(this), nfts);
        pricer = new OptionPricer();
        riskCache = new AssetRiskCache();
        reserve = address(0x1);
        backstopPool = address(0x2);
        vault = new Vault(address(weth), address(lpToken), address(oracle), address(pricer), address(riskCache), reserve, backstopPool);
        
        optionToken = new OptionToken(nfts[0], "Azuki", "Azuki", "https://");
        optionToken.initialize(address(vault));
        vault.addMarket(nfts[0], uint32(GENERAL_UNIT) / 10, address(optionToken));
        vault.activateMarket(nfts[0]);
        lpToken.initialize(address(vault), maximumVaultBalance);
        pricer.initialize(address(vault), address(riskCache), address(oracle));
        
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        NFTCallOracle.UpdateInput[][] memory inputs = new NFTCallOracle.UpdateInput[][](1);
        inputs[0] = new NFTCallOracle.UpdateInput[](1);
        inputs[0][0] = NFTCallOracle.UpdateInput({
            price: 1000,     // 10 ether
            vol: 1000,      // 100 Vol,        
            index: 1
        });
        oracle.batchSetAssetPrice(indices, inputs);
        riskCache.updateAssetRisk(nfts[0], 0, 0);
    }

    function test_GetAssetPriceAndVol() public {
        (uint256 price, uint256 vol) = oracle.getAssetPriceAndVol(nfts[0]);
        assertEq(price, 1000 * UNIT / oracle.PRICE_UNIT());
        assertEq(vol, 1000 * UNIT / oracle.VOL_UNIT());
    }

    function test_GetAdjustedVol() public {
        uint256 amount = 10 ether;
        weth.mint();
        weth.approve(address(lpToken), amount);
        vault.deposit(amount, address(this));

        uint256 vol = oracle.getAssetVol(nfts[0]);
        uint256 adjustedVol_1 = pricer.getAdjustedVol(nfts[0], OptionType.LONG_CALL, 1200 * UNIT / oracle.PRICE_UNIT(), 1 ether);
        assertGt(adjustedVol_1, vol);
        
        // Here delta==0
        uint256 adjustedVol_2 = pricer.getAdjustedVol(nfts[0], OptionType.LONG_CALL, 1200 * UNIT / oracle.PRICE_UNIT(), 1.1 ether);
        assertEq(adjustedVol_2, adjustedVol_1);

        // Open a position then check again
        // vault.openPosition(collection, onBehalfOf, optionType, strikePrice, expiry, amount, maximumPremium);
    }


/*     function test_CannotSubtract43() public {
        vm.expectRevert(stdError.arithmeticError);
        testNumber -= 43;
    } */

}
