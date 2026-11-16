#!/bin/bash
# cloud-init for the ARCHIVE ZEBRA + LIGHTWALLETD node. Installs prerequisites and clones the
# stack. It intentionally does NOT guess the run config; finish per the live docs.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl git jq ufw htop

# Docker + compose plugin
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu || true

# Basic host firewall (belt-and-braces alongside the AWS security group)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 8233/tcp        # Zebra P2P
ufw --force enable

# Clone the open Zcash stack (Zebra + lightwalletd, Zaino optional)
mkdir -p /opt/zcash && cd /opt/zcash
git clone https://github.com/zecrocks/zcash-stack.git || true
chown -R ubuntu:ubuntu /opt/zcash

cat > /root/NEXT_STEPS.md <<'EOF'
NODE ROLE: archive Zebra 7.0.0 + lightwalletd v0.6.1  (mainnet, unpruned, NU7)

Docker is installed and /opt/zcash/zcash-stack is cloned. To finish:

1) cd /opt/zcash/zcash-stack ; read docs/ (workshop) and docker/ (compose).
2) Bring up Zebra (mainnet, archive) via docker compose, with the image pinned to
   zfnd/zebra:7.0.0 (not :latest) and CONFIG_FILE_PATH pointing at the mounted
   zebrad.toml. Expect ~270 GB of state and a ~11.5h sync from a snapshot.
   Watch: docker compose logs -f zebra
3) Run electriccoinco/lightwalletd:v0.6.1 on the same docker network, pointed at
   zebra:8232, with --donation-address set. Keep its gRPC bound to 127.0.0.1.
   Do NOT expose it directly.
4) Public endpoint = Caddy on :443 with automatic TLS, reverse-proxying to the
   local gRPC service. Point a domain's A record at this box first.
   NO logging of client IPs / addresses.
5) Verify: grpcurl <host>:443 ... GetLightdInfo  (or add as a custom server in a wallet).

Record the sync FINISH time; the benchmark needs it.
EOF
echo "cloud-init done" > /root/CLOUDINIT_DONE
