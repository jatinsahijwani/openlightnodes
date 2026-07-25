# Run your own Open Light Node

This is the heart of the project: the more independent operators, the more resilient and decentralized the network. If you run a node and add it to the endpoints list, you *are* the network. This guide gets you from nothing to a public, wallet-usable endpoint.

## What you need

- A server with **~4 vCPU, 16 GB RAM, and ~450 GB SSD** for an archive Zebra node (an archive node is required to serve wallets — a pruned node cannot, see the [benchmark report](./benchmark-report.md)).
- A **domain or subdomain** you control, so you can get a real TLS certificate wallets will trust.
- Basic comfort with Linux, SSH, and Docker.

Independent providers (Contabo, OVH, Hetzner, a local datacenter, or a home server) are encouraged over a single big cloud — provider diversity is part of the point.

## Steps

1. **Provision** an Ubuntu 22.04 box and harden it: SSH keys only, a firewall allowing 22 (your IP), 443, and 8233 (Zebra P2P).
2. **Install Docker**, then deploy Zebra + lightwalletd. The scripts and compose config in [`deploy/`](./deploy/) show a working setup; upstream [`zcash-stack`](https://github.com/zecrocks/zcash-stack) is the reference (note the fixes in our `deploy/` and PR history).
3. **Point a subdomain** (A record) at your server's IP. Use a static/elastic IP so it survives restarts.
4. **Front it with Caddy on :443** for automatic Let's Encrypt TLS, reverse-proxying to the local gRPC service. Keep the indexer bound to `127.0.0.1`.
5. **Disable logging** of client IPs and addresses (`log { output discard }` in Caddy). Publish a short privacy note.
6. **Verify** end-to-end from another machine:
   ```
   grpcurl -authority <your-domain> <ip>:443 \
     cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo
   ```
   You should see the current `blockHeight`. Then add it as a custom server in Zashi or YWallet and confirm a wallet syncs.

## Bootstrapping faster

A full sync from scratch takes many hours. Restore from a published snapshot instead:
- Snapshots are served throttled on a single connection — use **parallel HTTP range downloads** or the restore will crawl.
- If restoring an older Zebra snapshot, raise the peer target (e.g. `peerset_initial_target_size = 75`) or the node can stall on peer starvation before catch-up throughput normalises.

See the [benchmark report](./benchmark-report.md) findings for the specifics.

## Add your node to the network

Open a PR editing the endpoints table in [README.md](./README.md) with your endpoint, region, backend, and operator handle. Please confirm: no client-IP logging, TLS valid, and node at tip. Welcome aboard.

## Getting help

Open an issue, or reach out on the [forum thread](https://forum.zcashcommunity.com/t/56727). If you're onboarding through the Zcash India community, mention it — we can pair with you.
