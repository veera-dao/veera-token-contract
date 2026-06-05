import 'dotenv/config'
import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-foundry'
import '@layerzerolabs/toolbox-hardhat'
import 'hardhat-deploy'

import type { HardhatUserConfig } from 'hardhat/config'
import { EndpointId } from '@layerzerolabs/lz-definitions'

const PRIVATE_KEY = process.env.LZ_CONFIG_PRIVATE_KEY
const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : []

if (process.argv.includes('lz:oapp:wire') && !PRIVATE_KEY && !process.argv.includes('--safe') && !process.argv.includes('--dry-run')) {
  throw new Error('LZ_CONFIG_PRIVATE_KEY is not set in the environment variables, and --safe / --dry-run is not in use.')
}

const config: HardhatUserConfig = {
  paths: {
    sources: './src',
    tests: './test-hardhat', // Prevents collision with Foundry tests
  },
  solidity: {
    version: '0.8.24',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
      evmVersion: 'cancun',
    },
  },
  networks: {
    base: {
      url: process.env.BASE_RPC_URL || 'https://mainnet.base.org',
      accounts,
      // @ts-ignore
      eid: EndpointId.BASE_V2_MAINNET,
    },
    bsc: {
      url: process.env.BSC_RPC_URL || 'https://bsc-dataseed.binance.org',
      accounts,
      // @ts-ignore
      eid: EndpointId.BSC_V2_MAINNET,
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org',
      accounts,
      // @ts-ignore
      eid: EndpointId.BASESEP_V2_TESTNET,
    },
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC_URL || 'https://data-seed-prebsc-1-s1.binance.org:8545',
      accounts,
      // @ts-ignore
      eid: EndpointId.BSC_V2_TESTNET,
    },
  },
}

export default config
