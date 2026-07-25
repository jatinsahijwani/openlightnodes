#!/bin/bash
# cloud-init for the ZAKURA (pruned) + ZAINO node. Installs prerequisites and clones
# both repos. Finish per the live docs — Zakura's README is the source of truth for
# build/run + snapshot bootstrap.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl git jq ufw htop build-essential

curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu || true

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 8233/tcp
ufw --force enable

mkdir -p /opt/zcash && cd /opt/zcash
git clone https://github.com/zakura-core/zakura.git || true
git clone https://github.com/zecrocks/zcash-stack.git || true
chown -R ubuntu:ubuntu /opt/zcash

cat > /root/NEXT_STEPS.md <<'EOF'
NODE ROLE: Zakura (pruned) + Zaino

Docker installed; /opt/zcash/zakura and /opt/zcash/zcash-stack cloned. To finish:

1) cd /opt/zcash/zakura ; read README for run instructions + PRUNED mode + the
   snapshot bootstrap (pruned snapshot ~11 GB, bootstrap target < 2 min).
2) Run Zakura in pruned mode. If using zcashd-RPC-compat, note which tools rely on it.
   Expect ~4h (or minutes with snapshot) vs Zebra's ~20h — capture this timing.
3) Point Zaino (from zcash-stack) at the Zakura node's RPC/state. Keep gRPC on localhost.
4) Public endpoint via Caddy :443 + TLS, no logging. Point a domain A record here.
5) Verify with grpcurl / a wallet custom server.

Record: bootstrap/sync FINISH time, and disk used after sync (du -sh of the data dir).
EOF
echo "cloud-init done" > /root/CLOUDINIT_DONE
