import fs from 'fs'
import path from 'path'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'
import { MSG_TYPE_SEND, CONTRACT_NAME } from './layerzero.constants'

interface NetworkConfig {
  rpcIdentifier?: string
  expectedBridgeAddress?: string
  lzEndpoint?: string
  lzEid?: string
  lzConfirmations?: number
  lzRequiredDVNs?: string[]
  lzReceiveGas?: number
  [key: string]: any
}

interface Manifest {
  networks: Record<string, NetworkConfig>
  [key: string]: any
}

// Helper to resolve the correct manifest path dynamically
function resolveManifestPath(): string {
  const envPath = process.env.DEPLOY_MANIFEST_PATH
  if (!envPath) {
    throw new Error('[layerzero.config.builder] DEPLOY_MANIFEST_PATH environment variable is not defined')
  }
  return path.isAbsolute(envPath) ? envPath : path.resolve(process.cwd(), envPath)
}

export function buildLayerZeroConfig() {
  return async function () {
    const manifestPath = resolveManifestPath()

    if (!fs.existsSync(manifestPath)) {
      throw new Error(`[layerzero.config.builder] Manifest file not found at ${manifestPath}`)
    }

    const manifestContent = fs.readFileSync(manifestPath, 'utf8')
    const manifest: Manifest = JSON.parse(manifestContent)

    // 1. Parse valid networks from manifest (ignore anvil/local 31337 or endpoint=0/bridge=0)
    const validNetworks: { chainId: string; config: NetworkConfig }[] = []

    for (const [chainId, config] of Object.entries(manifest.networks)) {
      const eid = Number(config.lzEid)
      const bridge = config.expectedBridgeAddress

      if (
        eid &&
        eid > 0 &&
        bridge &&
        bridge !== '0x0000000000000000000000000000000000000000'
      ) {
        validNetworks.push({ chainId, config })
      }
    }

    // 2. Create OmniPointHardhat adapters
    const adapters = validNetworks.map(({ config }) => {
      const adapter: OmniPointHardhat = {
        eid: Number(config.lzEid),
        contractName: CONTRACT_NAME,
        address: config.expectedBridgeAddress!,
      }
      return adapter
    })

    // 3. Security Check: mainnet must have a minimum of 2 required DVNs defined in manifest
    for (const { config } of validNetworks) {
      const isNetMainnet = config.rpcIdentifier && config.rpcIdentifier.includes('mainnet')
      if (isNetMainnet) {
        if (!config.lzRequiredDVNs || config.lzRequiredDVNs.length < 2) {
          throw new Error(
            `[Security Check] Mainnet network "${config.rpcIdentifier}" must have a minimum of 2 required DVNs defined in the manifest.`
          )
        }
      }
    }

    // Helper to get lzReceiveGas for a network
    const getLzReceiveGas = (config: NetworkConfig): number => {
      if (config.lzReceiveGas === undefined) {
        throw new Error(
          `[layerzero.config.builder] lzReceiveGas not defined for network "${config.rpcIdentifier}" in the manifest.`
        )
      }
      return Number(config.lzReceiveGas)
    }

    // Helper to construct EVM enforced options
    const getEnforcedOptions = (receiveGas: number): OAppEnforcedOption[] => [
      {
        msgType: MSG_TYPE_SEND,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: receiveGas,
        value: 0,
      },
    ]

    // Helper to get confirmations for a network
    const getConfirmations = (config: NetworkConfig): number => {
      if (config.lzConfirmations === undefined) {
        throw new Error(
          `[layerzero.config.builder] Network lzConfirmations not defined for network "${config.rpcIdentifier}" in the manifest.`
        )
      }
      return Number(config.lzConfirmations)
    }

    // 4. Generate connections for a full mesh (every network connected to every other network)
    const pathways: TwoWayConfig[] = []

    for (let i = 0; i < validNetworks.length; i++) {
      for (let j = i + 1; j < validNetworks.length; j++) {
        const netA = validNetworks[i]
        const netB = validNetworks[j]
        const adapterA = adapters[i]
        const adapterB = adapters[j]

        const confirmationsA = getConfirmations(netA.config)
        const confirmationsB = getConfirmations(netB.config)

        const gasA = getLzReceiveGas(netA.config)
        const gasB = getLzReceiveGas(netB.config)

        // Union required DVNs of both networks
        const unionRequiredDVNs = Array.from(
          new Set([
            ...(netA.config.lzRequiredDVNs || []),
            ...(netB.config.lzRequiredDVNs || [])
          ])
        )

        pathways.push([
          adapterA,
          adapterB,
          [unionRequiredDVNs, []],
          [confirmationsA, confirmationsB],
          [getEnforcedOptions(gasB), getEnforcedOptions(gasA)],
        ])
      }
    }

    const connections = await generateConnectionsConfig(pathways)

    return {
      contracts: adapters.map(adapter => ({ contract: adapter })),
      connections,
    }
  }
}
