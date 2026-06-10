## 1. Architecture & Design Decisions

### LayerZero V2 Bridging (MintBurnOFTAdapter)

The cross-chain bridging is powered by LayerZero V2 using a custom [VeeraMintBurnOFTAdapter](src/bridge/VeeraMintBurnOFTAdapter.sol).

* **Mechanism**: Rather than locking tokens in an escrow vault (Lock-and-Unlock pattern), the adapter utilizes a **Burn-and-Mint** pattern. When a user sends tokens to another chain, the adapter burns them directly from the user's wallet via `burnFrom`. On the destination chain, the corresponding adapter mints them back to the user via `mint`. This maintains a clean, uniform global supply without custodial honeypots.
* **Access Control**: The adapter **must** receive `MINTER_ROLE` (and only this adapter) on the local [Veera](src/Veera.sol) token contract to allow it to mint tokens on credit (bridge in) without any other entity having mint authority.
* **User Approval**: Users **must approve** this adapter address on the `Veera` token contract before calling the LayerZero `send` function.
* **Peer Configuration**: It is recommended to use LayerZero's official `lz` CLI or Hardhat/devtools configuration tasks for peer wiring.
* **Operational Phases**:
  1. **Deployment**: Deploying the bridge adapter contract using `DeployOFTAdapter.s.sol`.
  2. **Configuration**: Wire the peers by calling `setPeer` on the adapter (using `ConfigureOFTAdapter.s.sol`).
  3. **Activation**: Granting `MINTER_ROLE` to the adapter address on the token contract (via Gnosis Safe).
  *Note: These are strictly separate lifecycle phases handled by distinct tasks/transactions.*
* **Deterministic Bridge Address Invariant**:
  The bridge adapter address will only match across chains when token address, LayerZero endpoint, targetAdmin, salt, factory, bytecode, and compiler settings all match. Since LayerZero endpoints are network-specific, predicted bridge adapter addresses will typically differ across mainnets and testnets depending on these variables.
* **Limitations & Safety Guidelines**:
  * **Single Adapter per Chain**: Only one `OFTAdapter` should be deployed per chain for this token. Multiple adapters break unified liquidity and can lead to permanent token loss on destination chains.
  * **Fee-on-Transfer**: Fee-on-transfer / rebasing tokens are **not supported** by this adapter.

---

## 2. Deterministic CREATE2 Deployment Workflow

To achieve identical contract addresses across multiple EVM chains (e.g., Base and BSC, mainnet and testnet) using `CREATE2`, the deployer factory, the deployment salt, and the creation bytecode (which includes constructor arguments) must be **completely invariant**.

### Deterministic Inputs

| Input Parameter | Value | Description |
| :--- | :--- | :--- |
| **CREATE2 Factory** | `0x4e59b44847b379578588920cA78FbF26c0B4956C` | Standard keyless Arachnid Deterministic Deployment Proxy. |
| **Salt** | `0xe2713982c0efe119dc5260cee9928c24af6cc4c4dcbc5f5bdb83a77932c80847` | Salt used to offset the deployment address. |
| **Token Name** | `"Veera Token"` | Constructor argument: Name of the ERC20 token. |
| **Token Symbol** | `"VEERA"` | Constructor argument: Symbol of the ERC20 token. |
| **Bootstrap Admin** | `0x3188aF25805b403006c49e9D387FB17bb65A9f25` | Constructor argument: Temporary global admin EOA. |
| **Constructor Supply** | `0` | Constructor argument: Must be strictly 0 on all chains. |
| **Max Supply** | `1_000_000_000` ($10^{27}$ wei) | Constructor argument: Total supply cap (1 Billion tokens). |

> [!NOTE]
> **Custom CREATE2 Factories:** While `0x4e59b44847b379578588920cA78FbF26c0B4956C` is the industry-standard Arachnid keyless CREATE2 factory, the JSON manifest allows specifying a custom factory address under the `"factory"` key, as well as its codehash under `"factoryCodeHash"`.

### Deterministic Target Address

When the above parameters are compiled with Solidity **0.8.28** (using Cancun EVM, optimization enabled at 200 runs), the resulting deterministic CREATE2 contract address is:

$$\mathbf{0x6e398a93eAcc13CBCb3e9a7c7a0B73821220E532}$$

---

## 3. LayerZero Pathway Configuration & Wiring (Hardhat Suite)

While Foundry is used for compiling, testing, and deterministic CREATE2 contract deployments, LayerZero V2 configurations (such as peer wiring, pathway verification, send/receive library settings, enforced option parameters, and DVN settings) are managed via Hardhat using LayerZero’s official devtools (`@layerzerolabs/toolbox-hardhat`).

### 3.1 Single Source of Truth Address Invariant
To prevent configuration drift, all contract addresses are resolved dynamically on-the-fly from the deployment manifest specified by the `DEPLOY_MANIFEST_PATH` environment variable (e.g. [deploy_manifest.mainnet.json](deploy_manifest.mainnet.json)). We **never** hardcode deployed contract addresses across different configuration files.

### 3.2 Operational Scripts
The root `package.json` contains pre-configured scripts for pathway wiring and diagnostics.

| Action | Testnet (Base Sepolia ↔ BSC Testnet) | Mainnet (Base ↔ BSC) |
| :--- | :--- | :--- |
| **Configure Wiring & Peers** | `npm run lz:wire:testnet` | `npm run lz:wire:mainnet` |
| **Read Back Peers** | `npm run lz:peers:testnet` | `npm run lz:peers:mainnet` |
| **Read Back Config & DVNs** | `npm run lz:config:testnet` | `npm run lz:config:mainnet` |

### 3.3 Gnosis Safe Multisig Wiring Workflow
Because the `VeeraMintBurnOFTAdapter` contracts on Mainnet are owned by the Gnosis Safe multisig `targetAdmin` contract, wiring configuration transactions cannot be signed by a standard EOA private key. 

To wire pathways for Gnosis Safe-owned contracts:
1. Ensure your `.env` does not contain a `LZ_CONFIG_PRIVATE_KEY` (or leave it unset/empty).
2. Execute the wiring task. The LayerZero toolchain will automatically detect that no private key is present to sign, perform checks on-chain, and generate/propose the raw transaction payloads (calldata).
3. Copy the proposed calldata, target addresses, and value fields from the terminal.
4. Open the Gnosis Safe dashboard on the respective chain.
5. Launch the **Transaction Builder** app.
6. Input the target contract address, paste the generated calldata, and enqueue the transaction.
7. Repeat for all enqueued pathways, and sign/execute the transactions with the Safe owners.

### 3.4 Post-Wiring Verification & Diagnostics
Before authorizing a bridge to mint/burn tokens, you **must** perform a configuration check:
1. Run the wiring task on the selected network.
2. Query the actual configured peers using:
   ```bash
   npm run lz:peers:testnet
   ```
3. Query and export the pathway configurations, verifying dvns and confirmations:
   ```bash
   npm run lz:config:testnet
   ```
4. Verify that the output lists the correct expected peers and connection statuses.

### 3.5 Mainnet Security and DVN Policy
* **Testnet Policy:** A single DVN configuration (using the default `LayerZero Labs` DVN) is acceptable for initial integration testing.
* **Mainnet Policy:** A single-DVN configuration poses a central point of compromise. For mainnet production deployments:
  - Configure **multiple required DVNs** (e.g., Google Cloud DVN, Nethermind DVN, LayerZero Labs DVN) via `lzRequiredDVNs` in the network configuration block of the active manifest (e.g. [deploy_manifest.mainnet.json](deploy_manifest.mainnet.json)).
  - Alternatively, configure a required/optional threshold setup.
  - Do not enable production bridge use (e.g., granting `MINTER_ROLE` to the bridge adapter on the token contract) until the multi-DVN config is successfully wired and read back matching the approved security policy.

## 4 Live Integration Test Evidence (Base Sepolia ↔ BSC Testnet)
Verification evidence from executing the cross-chain integration tests:

* **Initial States**:
  * **Base Sepolia**: 999,999,898 VEERA
  * **BSC Testnet**: 2 VEERA

* **Cycle 1 (Base Sepolia ➔ BSC Testnet)**:
  * **Bridged Amount**: 1 VEERA
  * **LayerZero Native Fee**: 0.000221488614313199 ETH
  * **Transaction Hash**: [0xefdee8586c6f73604c0485e2ad9d7e635a6069e2d4347e0e599621383e338599](https://testnet.layerzeroscan.com/tx/0xefdee8586c6f73604c0485e2ad9d7e635a6069e2d4347e0e599621383e338599)
  * **Post-delivery BSC Testnet Balance**: 3 VEERA

* **Cycle 2 (BSC Testnet ➔ Base Sepolia)**:
  * **Bridged Amount**: 1 VEERA
  * **LayerZero Native Fee**: 0.000347596069246719 BNB
  * **Transaction Hash**: [0xac72620bf2e2e54e38e6d56abc7b4c2ce5f1f581c2f95f0232838353357d2bcb](https://testnet.layerzeroscan.com/tx/0xac72620bf2e2e54e38e6d56abc7b4c2ce5f1f581c2f95f0232838353357d2bcb)
  * **Post-delivery Base Sepolia Balance**: 999,999,898 VEERA
