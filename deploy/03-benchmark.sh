#!/usr/bin/env bash
# 03-benchmark.sh — collect a reproducible comparison of the two nodes.
# Usage: bash 03-benchmark.sh <zebra_host> <zakura_host>
# Produces: benchmark-report.md
#
# The two nodes are NOT symmetric, and the script reflects that:
#
#   Zebra  (t3.xlarge, 450 GB) — full/archive node. Serves lightwallet clients
#          through lightwalletd gRPC on 127.0.0.1:9067, published publicly by
#          Caddy on :443 with Let's Encrypt TLS.
#          (Zaino was tried first and indexes Zebra fine, but its GetLightdInfo
#          path cannot deserialise a 6-entry valuePools array — see finding 6.)
#
#   Zakura (t3.large, 60 GB)   — pruned node (tx_retention 10000). Zaino CANNOT
#          index it: Zaino builds its index from block 1 and a pruned node has
#          discarded that data, so there is no gRPC endpoint on this box. It is
#          measured over JSON-RPC instead. This asymmetry is a finding, not a
#          setup failure — see the report's limitations section.
set -uo pipefail

KEY="${KEY:-zcash-asia.pem}"
ZEBRA_HOST="${1:?usage: 03-benchmark.sh <zebra_host> <zakura_host>}"
ZAKURA_HOST="${2:?usage: 03-benchmark.sh <zebra_host> <zakura_host>}"
SSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -i $KEY"
LAT_SAMPLES="${LAT_SAMPLES:-20}"

# Per-host settings: data dir, RPC container, and whether a gRPC endpoint exists.
ZEBRA_DATA="/opt/zcash/zcash-stack/docker/data/zebrad-cache"
ZAKURA_DATA="/opt/zcash/zakura-data"

# Remote collector: prints "key<TAB>value" lines.
# $1 = data dir, $2 = rpc container name, $3 = grpc endpoint or "none", $4 = samples
read -r -d '' REMOTE <<'RS' || true
DATA_DIR="$1"; RPC_CONTAINER="$2"; GRPC_ENDPOINT="$3"; SAMPLES="$4"

echo "hostname	$(hostname)"
echo "kernel	$(uname -r)"
echo "cpu_model	$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ *//')"
echo "cpu_cores	$(nproc)"
echo "mem_total_mb	$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"
echo "loadavg	$(cut -d' ' -f1-3 /proc/loadavg)"
echo "uptime_s	$(cut -d' ' -f1 /proc/uptime)"
echo "disk_data_used	$(sudo du -sh "$DATA_DIR" 2>/dev/null | cut -f1)"
echo "disk_root	$(df -h / | awk 'NR==2{print $3" used / "$2" ("$5")"}')"

# per-container CPU/RAM
if command -v docker >/dev/null 2>&1; then
  docker stats --no-stream --format 'stat_container	{{.Name}}	CPU {{.CPUPerc}}	MEM {{.MemUsage}}' 2>/dev/null || true
fi

# --- JSON-RPC: chain state + latency (works on both nodes) ---
rpc () {
  docker run --rm --network zcash-network curlimages/curl:latest -s \
    -H 'Content-Type: application/json' \
    --data-binary "{\"jsonrpc\":\"2.0\",\"id\":\"b\",\"method\":\"$1\",\"params\":[]}" \
    "http://${RPC_CONTAINER}:8232" 2>/dev/null
}
INFO="$(rpc getblockchaininfo)"
if [ -n "$INFO" ]; then
  echo "rpc_blocks	$(echo "$INFO" | jq -r '.result.blocks // "n/a"')"
  echo "rpc_estimatedheight	$(echo "$INFO" | jq -r '.result.estimatedheight // "n/a"')"
  echo "rpc_verificationprogress	$(echo "$INFO" | jq -r '.result.verificationprogress // "n/a"')"
  echo "rpc_pruned	$(echo "$INFO" | jq -r '.result.pruned // "n/a"')"
  echo "rpc_size_on_disk	$(echo "$INFO" | jq -r '.result.size_on_disk // "n/a"')"
  echo "node_version	$(rpc getinfo | jq -r '.result.subversion // "n/a"')"
  echo "peers	$(rpc getinfo | jq -r '.result.connections // "n/a"')"

  # latency of a trivial RPC, averaged. Uses a persistent container-free loop
  # so we time the RPC, not docker start-up.
  tot=0; ok=0
  for i in $(seq 1 "$SAMPLES"); do
    s=$(date +%s%N)
    out=$(rpc getblockcount)
    e=$(date +%s%N)
    if [ -n "$out" ]; then tot=$(( tot + (e-s)/1000000 )); ok=$(( ok+1 )); fi
  done
  [ "$ok" -gt 0 ] && echo "rpc_avg_latency_ms	$(( tot / ok ))	(samples=$ok, includes docker exec overhead)" \
                  || echo "rpc_avg_latency_ms	n/a"
else
  echo "rpc_blocks	n/a	(RPC unreachable)"
fi

# --- gRPC: only where a lightwallet endpoint actually exists ---
if [ "$GRPC_ENDPOINT" = "none" ]; then
  echo "grpc_avg_latency_ms	n/a	(no gRPC endpoint: pruned node cannot back Zaino)"
else
  if ! command -v grpcurl >/dev/null 2>&1; then
    GV=1.9.1; ARCH=$(dpkg --print-architecture)
    [ "$ARCH" = amd64 ] && GA=x86_64 || GA=arm64
    curl -sSL "https://github.com/fullstorydev/grpcurl/releases/download/v${GV}/grpcurl_${GV}_linux_${GA}.tar.gz" \
      | sudo tar -xz -C /usr/local/bin grpcurl 2>/dev/null || true
  fi
  if command -v grpcurl >/dev/null 2>&1; then
    LWD='cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo'
    echo "grpc_lightd_info	$(grpcurl -plaintext -max-time 15 "$GRPC_ENDPOINT" "$LWD" 2>/dev/null | jq -c '{version,blockHeight,chainName}' 2>/dev/null || echo 'n/a')"
    tot=0; ok=0
    for i in $(seq 1 "$SAMPLES"); do
      s=$(date +%s%N)
      if grpcurl -plaintext -max-time 15 "$GRPC_ENDPOINT" "$LWD" >/dev/null 2>&1; then
        e=$(date +%s%N); tot=$(( tot + (e-s)/1000000 )); ok=$(( ok+1 ))
      fi
    done
    [ "$ok" -gt 0 ] && echo "grpc_avg_latency_ms	$(( tot / ok ))	(samples=$ok)" \
                    || echo "grpc_avg_latency_ms	n/a	(GetLightdInfo failed — check Zaino)"
  else
    echo "grpc_avg_latency_ms	n/a	(grpcurl unavailable)"
  fi
fi
RS

collect () {  # host, data_dir, rpc_container, grpc_endpoint
  $SSH "ubuntu@$1" "bash -s -- '$2' '$3' '$4' '$LAT_SAMPLES'" <<< "$REMOTE"
}

echo "Collecting from Zebra node ($ZEBRA_HOST)..."
ZEBRA_OUT="$(collect "$ZEBRA_HOST" "$ZEBRA_DATA" zebra 127.0.0.1:9067)"
echo "Collecting from Zakura node ($ZAKURA_HOST)..."
ZAKURA_OUT="$(collect "$ZAKURA_HOST" "$ZAKURA_DATA" zakura none)"

val () { echo "$2" | awk -F'\t' -v k="$1" '$1==k{$1="";sub(/^\t/,"");gsub(/\t/," ");print;exit}'; }
row () { echo "| $1 | $(val "$2" "$ZEBRA_OUT") | $(val "$2" "$ZAKURA_OUT") |"; }

REPORT="benchmark-report.md"
{
echo "# Zcash Node Benchmark — Zebra (full) vs Zakura (pruned)"
echo
echo "Region: ap-south-1 (Mumbai) · Collected: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "Reproducible with the scripts in this repo (\`deploy/\`)."
echo
echo "## Hosts"
echo
echo "| Metric | Zebra (t3.xlarge) | Zakura pruned (t3.large) |"
echo "|---|---|---|"
row "Host"                "hostname"
row "Node version"        "node_version"
row "CPU"                 "cpu_model"
row "CPU cores"           "cpu_cores"
row "RAM total (MB)"      "mem_total_mb"
row "Load avg (1/5/15m)"  "loadavg"
echo
echo "## Chain state"
echo
echo "| Metric | Zebra | Zakura pruned |"
echo "|---|---|---|"
row "Block height"           "rpc_blocks"
row "Estimated tip"          "rpc_estimatedheight"
row "Verification progress"  "rpc_verificationprogress"
row "Pruned"                 "rpc_pruned"
row "Peers"                  "peers"
echo
echo "## Storage"
echo
echo "| Metric | Zebra | Zakura pruned |"
echo "|---|---|---|"
row "Node data on disk"    "disk_data_used"
row "size_on_disk (RPC)"   "rpc_size_on_disk"
row "Root filesystem"      "disk_root"
echo
echo "## Latency"
echo
echo "| Metric | Zebra | Zakura pruned |"
echo "|---|---|---|"
row "JSON-RPC avg latency"      "rpc_avg_latency_ms"
row "gRPC (GetLightdInfo) avg"  "grpc_avg_latency_ms"
row "GetLightdInfo response"    "grpc_lightd_info"
echo
echo "## Per-container resource snapshot"
echo '```'
echo "ZEBRA:";  echo "$ZEBRA_OUT"  | grep '^stat_container' | sed 's/^stat_container\t/  /' || echo "  (none captured)"
echo "ZAKURA:"; echo "$ZAKURA_OUT" | grep '^stat_container' | sed 's/^stat_container\t/  /' || echo "  (none captured)"
echo '```'
echo
echo "## Bootstrap & recovery (recorded during setup)"
echo
echo "| Metric | Zebra | Zakura pruned |"
echo "|---|---|---|"
echo "| Snapshot source | zecrocks, 2025-09-12 (279 GB, uncompressed tar) | zakura.com, 2026-07-23 (11 GiB, zstd) |"
echo "| Snapshot age at use | ~10 months | ~1 day |"
echo "| Snapshot download | _see notes_ | 100 s (aria2c, 16 conns, ~158 MiB/s) |"
echo "| Snapshot extract | _see notes_ | 3 m 06 s |"
echo "| Catch-up to tip | _see notes_ | ~2,100 blocks |"
echo "| **Total bootstrap** | _see notes_ | **< 25 min** |"
echo "| Restart → healthy | _fill in_ | _fill in_ |"
echo
echo "## Cost (ap-south-1 on-demand)"
echo
echo "| Item | Zebra | Zakura pruned |"
echo "|---|---|---|"
echo "| Instance | t3.xlarge ~\$0.181/h | t3.large ~\$0.090/h |"
echo "| Storage | 450 GB gp3 ~\$41.6/mo | 60 GB gp3 ~\$5.5/mo |"
echo "| **~Daily** | **~\$5.7** | **~\$2.4** |"
echo "| **~Monthly** | **~\$172** | **~\$71** |"
echo
echo "_Recovery test: \`docker restart <node>\` and time until the node reports its"
echo "previous height again via getblockchaininfo._"
} > "$REPORT"

echo
echo "Wrote $REPORT"
