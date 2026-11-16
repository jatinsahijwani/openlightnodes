# Open Light Nodes

Independent, community-run Zcash light client infrastructure, starting in Asia.

Most Zcash wallets reach the chain through light client servers: [Zodl](https://zodl.com) (formerly Zashi), [Zkool](https://github.com/hhanh00/zkool2) (the successor to Ywallet, which is deprecated for Zcash), [Zingo!](https://zingolabs.org), and others. That layer is still concentrated on a small number of operators and providers, with little independent presence in Asia. **Open Light Nodes** is an effort to change that: run independent, geographically distributed light client endpoints on the modern Zebra + lightwalletd stack (with Zaino planned), make them trivially reproducible, and grow an operator community rather than a single service.

This repo is fully open. Everything used to stand up and measure a production endpoint is here, so anyone can reproduce it, audit it, or run their own node.

## Live endpoints

| Endpoint | Region | Backend | Notes |
|---|---|---|---|
| `zebra.openlightnodes.org:443` | Mumbai (in) | Zebra `7.0.0` (archive) + lightwalletd `v0.6.1` | TLS (Let's Encrypt), no client-IP logging, NU7-ready |

More regions and independent operators coming. See [ROADMAP.md](./ROADMAP.md).

### NU7-ready

The endpoint follows NU7, which activated on Mainnet at block 3,543,405, and
survived the earlier Ironwood upgrade (NU6.3, block 3,428,143). Verified over the
public endpoint with [zecping](https://github.com/zecrocks/zecping):

```
$ ./zecping -addr zebra.openlightnodes.org:443 -donation
OK (380.52ms): height=3578414 server=zebra.openlightnodes.org:443 lwd=v0.6.1 zcd=/Zebra:7.0.0/ ipv=ipv4 ip=13.204.208.40 donation=u1hkw4duxfr7vrxl472p8chuuqzzqxnxrtle7pnt95vkh87dnuwwzz25zhqwswlr7vz3tsur0yc3gnxn5j7sna5k8v36wdwvr65wvvqyeek5cqnhv4vg5c8xe8fjwk74ngrxakvlrwcz6wud5n95j8rnvddmzqyxrjyq2ns8gfny0q845p
# verified 2026-11-16
```

Zebra releases are supported for a limited window and then halt on purpose.
Zebra 7.0.0 reports support until block 3,684,728, so the node must be upgraded
to the next Zebra release before then.

## Status page

Live health and uptime, by region: **[status.openlightnodes.org](https://status.openlightnodes.org)**

Each endpoint is watched two ways. A push monitor checks tip lag via
`GetLightdInfo` against an independent reference tip from other operators, and
then actually requests a block near the tip with `GetBlock`. The heights in
`GetLightdInfo` come from our own backend node, so they stay green even if the
indexer is wedged or the node has forked off at a network upgrade; comparing with
other operators and asking for a real block catches both. A TCP check on `:443`
also tracks TLS certificate expiry. Outage history is kept publicly. The monitor
runs on a separate host from the nodes, so the page stays up when a node does
not. Setup is documented in [docs/status-page.md](./docs/status-page.md).

## Principles

- **Privacy by default.** No logging of client IPs or addresses. Caddy access logging is disabled outright. A clear, public privacy policy.
- **Independent and multi-operator.** The goal is many operators on many providers and regions, not one central service. See [RUN-A-NODE.md](./RUN-A-NODE.md).
- **Roadmap-aligned.** Built on Zebra + lightwalletd, the post-zcashd stack, with a move to Zaino planned.
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

**Key finding:** a pruned node cannot back a lightwallet endpoint, because the indexer needs the full block history that pruning discards. That is why our serving node is archive Zebra. The limitation is pruning, not Zakura itself: Zakura's real value for operators is bootstrapping a node fast. The benchmark was run on Zakura 1.0.3. Zakura (from [Valar Group](https://valargroup.dev), aligned with [Project Tachyon](https://tachyon.z.cash/)) has since moved quickly to the v1.8 line (v1.8.7 stable, v1.8.8 pre-release as of November 2026) and tracks NU7. Details and reproduction steps are in the report.

## Run your own node

See [RUN-A-NODE.md](./RUN-A-NODE.md). If you bring one up, open a PR adding it to the endpoints table. That's how this becomes a real network.

## Status

Early. One production endpoint live, benchmark published, deployment scripts working, public status page up. Additional operators and regions are next. Treat endpoints as best-effort until redundancy lands.

## Credits

Built on the work of others: [Zebra](https://github.com/ZcashFoundation/zebra) (Zcash Foundation), [lightwalletd](https://github.com/zcash/lightwalletd), [Zaino](https://github.com/zingolabs/zaino) (Zingo Labs), [Zakura](https://github.com/zakura-core/zakura), and [`zcash-stack`](https://github.com/zecrocks/zcash-stack) (zec.rocks). This project complements, and does not compete with, existing operators.

Discussion: [Zcash Community Forum thread](https://forum.zcashcommunity.com/t/56727).

## License

MIT. See [LICENSE](./LICENSE).
