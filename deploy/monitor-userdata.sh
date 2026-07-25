#!/bin/bash
# cloud-init for the STATUS PAGE / MONITOR box.
#
# Deliberately separate from the node box: if the monitor lived on the node, the
# status page would go dark exactly when the node failed.
#
# Installs Docker, jq and grpcurl, runs Uptime Kuma bound to 127.0.0.1:3001, and
# installs Caddy with a Caddyfile for status.openlightnodes.org.
#
# Caddy is intentionally left STOPPED AND DISABLED. Two reasons:
#   1. Requesting a certificate before the DNS A record resolves burns Let's
#      Encrypt failure attempts against the rate limit.
#   2. Uptime Kuma grants admin to whoever first visits it. Exposing 443 before
#      the owner has created the admin account is an account-takeover window.
# Start it only after DNS resolves and the admin account exists.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg jq ufw debian-keyring debian-archive-keyring apt-transport-https

# --- Docker ---
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu || true

# --- grpcurl (health-push.sh needs it) ---
GV=1.9.1
curl -sSL "https://github.com/fullstorydev/grpcurl/releases/download/v${GV}/grpcurl_${GV}_linux_x86_64.tar.gz" \
  | tar -xz -C /usr/local/bin grpcurl
chmod +x /usr/local/bin/grpcurl

# --- host firewall, mirroring the security group ---
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
ufw --force enable

# --- Uptime Kuma, reachable only from localhost ---
docker run -d --restart=always \
  -p 127.0.0.1:3001:3001 \
  -v uptime-kuma:/app/data \
  --name uptime-kuma \
  louislam/uptime-kuma:1

# --- Caddy from the official repo ---
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

cat > /etc/caddy/Caddyfile <<'EOF'
# Public TLS front for the Uptime Kuma status page.
#
# Only port 443 is open in the security group, so ACME uses the TLS-ALPN-01
# challenge rather than HTTP-01. That works without port 80.
status.openlightnodes.org {
	# Do not log visitor IP addresses. Same privacy posture as the node.
	log {
		output discard
	}

	reverse_proxy 127.0.0.1:3001
}
EOF

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile || true

# Keep it down until DNS resolves and the Kuma admin account is created.
systemctl stop caddy || true
systemctl disable caddy || true

cat > /root/NEXT_STEPS.md <<'EOF'
STATUS PAGE MONITOR BOX

Running now:
  - uptime-kuma  on 127.0.0.1:3001  (not publicly reachable)
  - caddy        INSTALLED BUT STOPPED AND DISABLED (deliberate, see below)

Installed: docker, jq, grpcurl, /usr/local/bin/health-push.sh

To finish, in this order:

1) Create the Kuma admin account over an SSH tunnel, BEFORE exposing 443.
   Uptime Kuma gives admin to the first visitor, so do this first.
   From your laptop:
     ssh -i zcash-asia.pem -L 3001:127.0.0.1:3001 ubuntu@<ELASTIC_IP>
   then open http://127.0.0.1:3001 and create the admin user.

2) Point DNS at this box:
     status.openlightnodes.org.  A  <ELASTIC_IP>
   Confirm with:  dig +short status.openlightnodes.org

3) Only then start Caddy, so the certificate request succeeds first time:
     sudo systemctl enable --now caddy
     sudo journalctl -u caddy -f      # watch for "certificate obtained successfully"

4) In the Kuma UI create the monitors (see docs/status-page.md step 4), then add
   the push URL to cron:
     ( crontab -l 2>/dev/null; echo "* * * * * PUSH_URL='https://status.openlightnodes.org/api/push/XXXXXXXX' /usr/local/bin/health-push.sh" ) | crontab -
EOF

echo "cloud-init done" > /root/CLOUDINIT_DONE
