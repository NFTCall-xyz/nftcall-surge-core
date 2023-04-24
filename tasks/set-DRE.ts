import {
    HardhatRuntimeEnvironment
} from 'hardhat/types';
import { task } from 'hardhat/config';
import {DRE, setDRE} from '../scripts/utils';

task(`set-DRE`, `Inits the DRE, to have access to all the plugins' objects`)
  .setAction(async (_, _DRE) => {
    if (!DRE) {
        console.log('- Enviroment');
        console.log('  - Network :', _DRE.network.name);
        setDRE(_DRE);
    };
})
