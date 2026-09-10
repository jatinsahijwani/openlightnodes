# Open Light Nodes

Independent, community-run Zcash light client infrastructure — starting in Asia.

Most Zcash wallets (Zashi, YWallet, and others) reach the chain through light client servers. That layer is still concentrated on a small number of operators and providers, with little independent presence in Asia. **Open Light Nodes** is an effort to change that: run independent, geographically distributed light client endpoints on the modern Zebra + Zaino/lightwalletd stack, make them trivially reproducible, and grow an operator community rather than a single service.

This repo is fully open. Everything used to stand up and measure a production endpoint is here, so anyone can reproduce it, audit it, or run their own node.

## Live endpoints

| Endpoint | Region | Backend | Notes |
|---|---|---|---|
| `zebra.openlightnodes.org:443` | Mumbai (in) | Zebra archive + lightwalletd `v0.5.4` | TLS (Let's Encrypt), no client-IP logging |

More regions and independent operators coming — see [ROADMAP.md](./ROADMAP.md).

## Status page

Live health and uptime, by region: **[status.openlightnodes.org](https://status.openlightnodes.org)**

Each endpoint is watched two ways: a push monitor that checks tip lag via
`GetLightdInfo` and then actually requests a block near the tip with `GetBlock`
(the heights alone come from the backend node, so they stay green even if the
indexer is wedged — only asking for a real block catches that), and a TCP check
on `:443` that also tracks TLS certificate expiry. Outage history is
kept publicly. The monitor runs on a separate host from the nodes, so the page
stays up when a node does not. Setup is documented in
[docs/status-page.md](./docs/status-page.md).

## Principles

- **Privacy by default.** No logging of client IPs or addresses. Caddy access logging is disabled outright. A clear, public privacy policy.
- **Independent and multi-operator.** The goal is many operators on many providers and regions, not one central service. See [RUN-A-NODE.md](./RUN-A-NODE.md).
- **Roadmap-aligned.** Built on Zebra + Zaino/lightwalletd, the post-zcashd stack.
- **Reproducible.** Every deployment step and benchmark is scripted and public.

## What's in here

```
.
├── deploy/               # AWS provisioning, node + monitor bootstrap, benchmark, health push
├── benchmark-report.md   # Zebra (archive) vs Zakura (pruned), fully measured
├── docs/status-page.md   # how the public status page is built
├── RUN-A-NODE.md         # how to run your own independent node
├── ROADMAP.md            # phased plan
└── CONTRIBUTING.md       # how to contribute / add your operator
```

## Benchmark highlight

A measured, like-for-like comparison at the same chain tip ([full report](./benchmark-report.md)):

| | Zebra (archive) | Zakura (pruned) |
|---|---|---|
| Node data on disk | 259 GB | 14 GB (~19× smaller) |
| Time to a synced node | ~11.5 h | < 25 min |
| Node RAM at tip | 2.17 GiB | 649 MiB |
| Can serve lightwallet clients | **Yes** | **No** |

**Key finding:** a pruned node cannot back a lightwallet endpoint — the indexer needs the full block history that pruning discards. Zakura's real value for operators is bootstrapping the *archive* node fast, not pruning. Details and reproduction steps are in the report.

## Run your own node

See [RUN-A-NODE.md](./RUN-A-NODE.md). If you bring one up, open a PR adding it to the endpoints table — that's how this becomes a real network.

## Status

Early. One production endpoint live, benchmark published, deployment scripts working. A public status page and additional operators are next. Treat endpoints as best-effort until the status page and redundancy land.

## Credits

Built on the work of others: [Zebra](https://github.com/ZcashFoundation/zebra) (Zcash Foundation), [Zaino](https://github.com/zingolabs/zaino) (Zingo Labs), [lightwalletd](https://github.com/zcash/lightwalletd), [Zakura](https://github.com/zakura-core/zakura), and [`zcash-stack`](https://github.com/zecrocks/zcash-stack) (zec.rocks). This project complements, and does not compete with, existing operators.

Discussion: [Zcash Community Forum thread](https://forum.zcashcommunity.com/t/56727).

## License

MIT — see [LICENSE](./LICENSE).
