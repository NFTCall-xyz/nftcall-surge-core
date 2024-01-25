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


contract VaultTest is Test {
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
        weth = new MintableERC20("WETH", "WETH", maximumVaultBalance);
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

    function onERC721Received(
      address, 
      address, 
      uint256, 
      bytes calldata
    )external pure returns(bytes4) {
      return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    } 

    function testFuzz_VaultDeposit(uint256 amount) public {
        // vm.prank(address(vault));
        vm.assume(amount <= maximumVaultBalance);
        weth.mint();
        weth.approve(address(lpToken), amount);
        vault.deposit(amount, address(this));
        assertEq(weth.balanceOf(address(lpToken)), amount);
        assertEq(lpToken.lockedBalanceOf(address(this)), amount);
    }

    function testFuzz_VaultWithdrawBeforeReleaseTime(uint256 amount) public {
        // vm.prank(address(vault));
        vm.assume(amount <= maximumVaultBalance && amount > 0);
        weth.mint();
        weth.approve(address(lpToken), amount);
        vault.deposit(amount, address(this));
        vm.expectRevert();
        vault.withdraw(amount, address(this));
    }

    function testFuzz_VaultWithdrawAfterReleaseTime(uint256 amount) public {
        vm.assume(amount <= maximumVaultBalance && amount > 1 ether);
        weth.mint();
        weth.approve(address(lpToken), amount);
        vault.deposit(amount, address(this));
        lpToken.approve(address(vault), amount);
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert();
        vault.withdraw(amount, address(this));
        vault.withdraw(amount/2, address(this));
    }

    function test_OpenOption() public {
        uint256 amount = 100 ether;
        address alice = address(0x12);
        vm.prank(alice);
        weth.mint();
        vm.prank(alice);
        weth.approve(address(lpToken), amount);
        vm.prank(alice);
        vault.deposit(amount, alice);

        // vm.prank(address(this));
        weth.mint();
        weth.approve(address(vault), 2 ether);
        (uint256 pid, uint256 premium) = vault.openPosition(nfts[0], address(this), OptionType.LONG_CALL, 1200 * UNIT / oracle.PRICE_UNIT(), 6 days, 1 * UNIT, 1 ether);
        console.log(pid, premium);
    }

    function testFuzz_ActiveOption_OnlyKeeper() public {}

    function testFuzz_CloseOption() public {}

/*     function test_CannotSubtract43() public {
        vm.expectRevert(stdError.arithmeticError);
        testNumber -= 43;
    } */

}
