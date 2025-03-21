# Staging environments

We have 2 staging environments for testing the Octant v2 Core:
- fork of Sepolia
- fork of Mainnet

Both of them are running using [Tenderly Virtual TestNets] and Kubernetes clusters deployed in Google Cloud Platform.

Access to environments is limited to VPN, Kubernetes clusters and CI/CD runners.

## Deployed services

- Ethereum RPC node (proxied Tenderly Virtual Testnet RPC endpoint)
- Graph-node
- Gnosis Safe infrastructure

## Endpoints 

| Service                    | Fork of Sepolia                           | Fork of Mainnet                           |
|----------------------------|-------------------------------------------|-------------------------------------------|
| RPC node                   | `https://rpc.ov2st.octant.build/`         | `https://rpc.ov2sm.octant.build/`         |
| Safe frontend              | `https://safe.ov2st.octant.build/`        | `https://safe.ov2sm.octant.build/`        |
| Safe config service        | `https://cfg.ov2st.octant.build/`         | `https://cfg.ov2sm.octant.build/`         |
| Graph node client endpoint | `https://graph.ov2st.octant.build/`       | `https://graph.ov2sm.octant.build/`       |
| Graph node admin endpoint  | `https://graph-admin.ov2st.octant.build/` | `https://graph-admin.ov2sm.octant.build/` |




[Tenderly Virtual TestNets]: https://docs.tenderly.co/virtual-testnets
