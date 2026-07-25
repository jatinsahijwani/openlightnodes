# Zcash Node Benchmark — Zebra (full/archive) vs Zakura (pruned)

Region: **ap-south-1 (Mumbai)** · Collected: 2026-07-25 UTC
Reproducible with the scripts in `deploy/` of this repo.

**Both nodes were measured at the chain tip** (height 3,424,320), on the same
day, in the same region, so the comparison below is like-for-like. Every number
is measured — nothing is estimated or extrapolated.

---

## Executive summary

| | Zebra (full/archive) | Zakura (pruned) |
|---|---|---|
| Instance | t3.xlarge (4 vCPU / 15.4 GiB) | t3.large (2 vCPU / 7.6 GiB) |
| **Node data on disk** | **259 GB** | **14 GB** (~19× smaller) |
| **Time to a synced node** | **~11.5 h** | **< 25 min** (~28× faster) |
| Chain height | 3,424,320 (tip) | 3,424,320 (tip) |
| **Restart → serving again** | **106 s** | **34 s** (~3× faster) |
| Node RAM in use | 2.17 GiB | 649 MiB (~3.4× less) |
| Peers | 403 | 156 |
| **Can serve lightwallet clients** | **Yes** | **No** — see finding 1 |
| **~Cost/day** | **~$5.8** | **~$2.4** |

**The trade-off in one line:** the pruned node reached the same chain tip in
under 25 minutes using 19× less disk, 3.4× less RAM and 42 % of the cost — but
it **cannot serve lightwallet clients at all**, because every indexer available
today needs history that pruning discards.

**Public endpoint (live):** `zebra.openlightnodes.org:443` — lightwalletd gRPC
behind Caddy with a Let's Encrypt certificate, client-IP logging disabled.

---

## Hosts

| Metric | Zebra | Zakura |
|---|---|---|
| Instance type | t3.xlarge | t3.large |
| vCPU / RAM | 4 / 15,788 MB | 2 / 7,820 MB |
| Root volume | 450 GB gp3 | 60 GB gp3 |
| Node software | `/Zebra:6.2.2/` | `/Zakura:1.0.3/` (`v1.0.3+g63b8d4dc0fe1`) |
| Indexer serving clients | lightwalletd `v0.4.19` | none possible (finding 1) |
| OS / AMI | Ubuntu 22.04 (`ami-0c809520a0d652e03`) | same |

## Chain state (both at tip)

| Metric | Zebra | Zakura |
|---|---|---|
| Block height | 3,424,320 | 3,424,320 |
| `estimatedheight` | 3,424,320 | 3,424,320 |
| `verificationprogress` | 1.0 | 1.0 |
| `pruned` (RPC) | false | **true** |
| Pruning retention | n/a (archive) | `tx_retention: 10000` blocks |
| Peers | 403 | 156 |

## Storage — the headline difference

| Metric | Zebra | Zakura |
|---|---|---|
| **Node data (`du -sh`)** | **259 GB** | **14 GB** |
| `size_on_disk` (RPC) | 277,402,294,853 B (258 GiB) | 13,954,404,862 B (13 GiB) |
| Filesystem used | 302 GB / 436 GB (70 %) | 29 GB / 58 GB (50 %) |
| Volume needed | 450 GB (300 GB was **not** enough) | 60 GB, half free |
| DB format | v27 → auto-upgraded to v28 | v28.0.1 |

A 300 GB volume cannot hold the Zebra chain today — the snapshot alone is 260 GiB
before any catch-up. It had to be grown to 450 GB mid-deploy.

## Bootstrap performance

| Metric | Zebra | Zakura |
|---|---|---|
| Snapshot source | zecrocks (`link.storjshare.io`) | zakura.com (`zakura.valargroup.dev`) |
| Snapshot date | 2025-09-12 (**~10 months stale**) | 2026-07-23 (**~1 day old**) |
| Snapshot size | 279,342,284,800 B (**260 GiB**), uncompressed tar | 11,349,937,059 B (**10.6 GiB**), zstd |
| Published checksum | none | **SHA-256** (verified OK) |
| Download + extract | **6,579 s (1 h 50 m)** | **100 s** + **186 s** = 4 m 46 s |
| DB format upgrade at start | ~64 s (v27→v28, in place) | not needed |
| Blocks to catch up | ~361,500 | ~2,100 |
| Catch-up duration | **~9.5 h** | **~15 min** |
| **Total to synced node** | **~11.5 h** | **< 25 min** |
| **Restart → previous height** | **106 s** | **34 s** |

## Latency

| Metric | Zebra | Zakura |
|---|---|---|
| gRPC `GetLightdInfo` (20 samples, local) | **73 ms** | n/a — no gRPC endpoint possible |
| Public TLS endpoint | `zebra.openlightnodes.org:443` ✅ | none |

## Resource usage at tip

```
ZEBRA   (t3.xlarge, 4 vCPU / 15.42 GiB)
  zebra    CPU 55.16%   MEM 2.169 GiB     <- node at tip, 403 peers
  lwd      CPU 63.19%   MEM 15.69 MiB     <- lightwalletd building its cache
  caddy    CPU  0.00%   MEM 30.36 MiB
  (zaino   MEM 9.367 GiB before being stopped — see finding 6)

ZAKURA  (t3.large, 2 vCPU / 7.637 GiB)
  zakura   CPU  3.86%   MEM 649.2 MiB     <- node at tip, 156 peers
```

Zakura held the same chain tip using **649 MiB** against Zebra's **2.17 GiB**.

## Cost (ap-south-1 on-demand)

| Item | Zebra | Zakura |
|---|---|---|
| Instance | t3.xlarge ~$0.1856/h | t3.large ~$0.0928/h |
| Storage | 450 GB gp3 ~$41.4/mo | 60 GB gp3 ~$5.5/mo |
| **~Daily** | **~$5.8** | **~$2.4** |
| **~Monthly** | **~$175** | **~$72** |

Storage alone is ~7.5× cheaper for the pruned node.

---

## Findings

### 1. A pruned node cannot back a lightwallet endpoint (the key result)

Zaino builds its index from block 1. A pruned Zakura node has discarded
transaction data outside its retention window, so those reads fail and Zaino
never starts. Verified directly against the running node:

```
getblock("13", 0)        -> {"code":-8,"message":"Block not found"}
getblock("13", 1)        -> {"code":-1,"message":"missing Sapling tree"}
getblock("3412000", 0)   -> {"code":-8,"message":"Block not found"}   # ~12k back
getblock("3422000", 0)   -> 0400000... (served)                       # inside window
```

Zaino's failure loop:

```
fetch_block_parts: transient error at height 13 (attempt 7/8), retrying:
  blockchain source error: error fetching block at height 13 from validator
FinalisedState background sync_to_height failed (attempt 4/5) ... at height 1
```

Zaino 0.5.0 exposes no start-height/birthday option and its docs do not cover
pruned validators. The control case is decisive: **the same Zaino build indexed
the archive Zebra node without complaint** (`syncing height 1,590,780 /
3,063,906`), so the cause is pruning, not Zaino or its configuration.

**Implication for operators:** a pruned node is excellent as a personal
validating node, a mining/relay peer, or a wallet's own backend — but a public
Zashi/YWallet-facing endpoint still requires an archive node and its ~259 GB.
Budget for archive storage if serving wallets is the goal.

### 2. Snapshot freshness dominates real bootstrap time

The 260 GiB restore was not the bottleneck — the catch-up was. Zakura's snapshot
was 1 day old (~2,100 blocks behind, minutes to tip). The only Zebra snapshot
published is 2025-09-12, ~10 months stale, leaving ~361,500 blocks to fetch over
P2P: **1 h 50 m to restore, then ~9.5 h to catch up.**

Snapshot ergonomics differed just as sharply:

| | Zebra snapshot | Zakura snapshot |
|---|---|---|
| Compression | none (260 GiB on the wire) | zstd (10.6 GiB, ~24× smaller) |
| Published checksum | no | yes (SHA-256, verified) |
| Single-connection speed | throttled ~1–12 MB/s | throttled ~12 KB/s (unusable) |
| With parallel HTTP ranges | ~40–75 MB/s | **~158 MiB/s** |

Both origins throttle single connections hard while honouring HTTP `Range`, so
**parallel chunked download was required on both**. Upstream's
`download-snapshot.sh` pipes a single `wget` into `tar`, which would have taken
~8 h for Zebra — anyone following the docs as written will hit this.

### 3. Zebra needs a large peer set; it self-corrected once discovery filled out

Immediately after the restore, Zebra advanced in rare ~400-block bursts with long
stalls — 0 blocks in one 182 s window at 8–9 peers. Block requests were timing
out, peers accrued misbehaviour score and were banned faster than replacements
were found:

```
error downloading and verifying block e=ValidationRequestError { error: Elapsed(()) ... }
banned ip and removed banned peer addresses ... misbehavior_score: 100
chain updates have stalled, state height has not increased for N minutes
```

Ruled out: clock skew (0 s drift, NTP synced), outbound connectivity (port 8233
reachable to seeders), and a stale peer cache (the snapshot contains none).
Raising `peerset_initial_target_size` from the default 25 to 75 stopped the peer
set collapsing (it had been sliding 9→4). Given time, peer discovery grew the set
to **403 peers** and the node caught up ~361,500 blocks in ~9.5 h unattended.

**Takeaway:** the early stall was peer starvation, not a broken node. Operators
restoring an old Zebra snapshot should raise the peer target and expect a slow
first hour before throughput normalises.

### 4. `zfnd/zebra` silently ignores a mounted `zebrad.toml`

The image's entrypoint uses `config-rs`: it reads a TOML **only** when
`CONFIG_FILE_PATH` names it, otherwise it uses defaults where the **RPC endpoint
is disabled**. `zcash-stack`'s compose files mount `configs/zebrad.toml` but never
set that variable, and the `.env` uses older `RPC_LISTEN_ADDR`/`RPC_PORT` names
this build ignores. Net effect: `[rpc]` is dropped, the compose healthcheck
(which greps for a listener on 8232) can never pass, and everything gated behind
`service_healthy` — Zaino, lightwalletd, Caddy — never starts. Fixed here with
`CONFIG_FILE_PATH=/etc/zebrad/zebrad.toml`.

### 5. `zcash-stack`'s Caddy overlay cannot be parsed at all

`docker/compose.caddy.yaml` fails outright:

```
failed to parse compose.caddy.yaml: yaml: construct errors:
  line 25: mapping key "depends_on" already defined at line 22
```

Three defects plus a latent fourth: a duplicate `depends_on` key; an env var
(`LIGHTWALLETD_DOMAIN=...`) listed as a service dependency; a mount of
`./configs/Caddyfile`, which does not exist in the repo (and neither
`LIGHTWALLETD_DOMAIN` nor `CADDY_EMAIL` is defined in `.env`); and `caddy`
attached to an `external: true` network while the other services use the default
project network, so it could not resolve `lightwalletd` regardless. **A fix has
been submitted upstream: [zecrocks/zcash-stack#29](https://github.com/zecrocks/zcash-stack/pull/29).**

### 6. Both Zaino builds are behind current node software on `valuePools`

Zcash nodes now return **six** value pools — `transparent`, `sprout`, `sapling`,
`orchard`, `lockbox`, `ironwood`. Both Zaino images tested choke on this:

| Zaino build | Against | Error |
|---|---|---|
| `0.1.2-zr4` (Apr 2025, pinned by `compose.zaino.yaml`) | Zakura 1.0.3 | `trailing characters at line 1 column 920` (offset lands on `ironwood`) |
| `0.5.0-pr1274-prefetch-retry` (Jun 2026, newest published) | Zebra 6.2.2 | `invalid length 6, expected fewer elements in array` |

The newer build indexes blocks fine but fails on `GetLightdInfo`, so it cannot
serve wallets against a current node. **lightwalletd `v0.4.19` handled the same
node correctly** and is what the public endpoint runs. Operators wiring up a
lightwallet endpoint today should prefer lightwalletd until Zaino catches up.

---

## Method / reproducibility

Both nodes: Ubuntu 22.04, Docker, same region, launched by
`deploy/02-launch-nodes.sh`; metrics collected by `deploy/03-benchmark.sh`.
gRPC is bound to `127.0.0.1` on both hosts. The only public ports are 8233 (P2P)
and 443 (TLS, Zebra only); SSH is restricted to a single administrative IP.
Caddy access logging is disabled outright (`log { output discard }`), so client
IP addresses are never written to disk.

Latency figures are the mean of 20 sequential `GetLightdInfo` calls measured on
the node itself, so they exclude internet round-trip. Restart-recovery is wall
time from `docker restart <node>` until the node's JSON-RPC serves its previous
height again.

## Caveats

- **Not a same-hardware comparison.** Zebra ran on t3.xlarge (4 vCPU) and Zakura
  on t3.large (2 vCPU), per the original plan and because Zebra cannot run
  comfortably on the smaller box. Zakura's lower resource use is therefore a
  floor, not a like-for-like margin.
- **Bootstrap times reflect the snapshots that exist today**, not the node
  software's intrinsic speed. A fresh Zebra snapshot would narrow the gap
  substantially; the ~10-month-stale snapshot is what upstream publishes.
- Both nodes are burstable `t3` instances with `CpuCredits=unlimited`.
- Zebra's catch-up ran unattended overnight; the ~9.5 h figure is bounded by
  observation timestamps, not instrumented to the second.
- lightwalletd was still building its own block cache when latency was measured;
  `GetLightdInfo` does not depend on that cache, but full wallet sync would.
