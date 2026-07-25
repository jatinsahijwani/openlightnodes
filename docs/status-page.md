# Public status page (Uptime Kuma)

A public page at `status.openlightnodes.org` showing endpoint health/uptime **by region**, with real serving/sync health — not just "port open."

## Design (read first)

- **Host the monitor on a separate small box**, not on the node. If it lived on the node, the page would go dark exactly when the node fails. A tiny box is plenty (Uptime Kuma is light): a `t3.micro` on AWS, or any ~$5/mo VPS. Running the *monitor* on a big cloud is fine — it's not the wallet-serving path, so it doesn't affect decentralization.
- **Two signals per endpoint:**
  1. **Push monitor (primary)** — a cron script on the monitor box calls `GetLightdInfo`, checks the node is serving *and* within a few blocks of the tip, and pushes the result. This is what makes the page meaningful.
  2. **TCP monitor (secondary)** — Uptime Kuma pings `host:443` directly; also tracks TLS cert expiry.
- **Group monitors by region** on the status page ("Mumbai · in"), so adding Singapore later is just a new group.

## Step 1 — Monitor box

Provision a small Ubuntu 22.04 box (t3.micro or a cheap VPS). Install Docker, plus the tools the health script needs:

```bash
curl -fsSL https://get.docker.com | sh
sudo apt-get update && sudo apt-get install -y jq
# grpcurl:
GV=1.9.1; curl -sSL "https://github.com/fullstorydev/grpcurl/releases/download/v${GV}/grpcurl_${GV}_linux_x86_64.tar.gz" | sudo tar -xz -C /usr/local/bin grpcurl
```

Open only ports 22 (your IP) and 443 in its security group. Point **`status.openlightnodes.org`** A record at this box's IP (use an Elastic/static IP).

## Step 2 — Run Uptime Kuma (bound to localhost)

```bash
docker run -d --restart=always \
  -p 127.0.0.1:3001:3001 \
  -v uptime-kuma:/app/data \
  --name uptime-kuma louislam/uptime-kuma:1
```

Binding to `127.0.0.1` means only the local Caddy can reach it — nothing on 3001 is exposed publicly.

## Step 3 — Caddy in front for TLS

Install Caddy and use this Caddyfile:

```
status.openlightnodes.org {
    reverse_proxy 127.0.0.1:3001
}
```

Reload Caddy. Visit `https://status.openlightnodes.org`, and create the Kuma admin account (do this promptly — the first visitor can claim admin).

## Step 4 — Create the monitors

In the Kuma UI:

1. **Push monitor** — New Monitor → Type **Push** → name `Mumbai — lightwalletd (height/lag)`, heartbeat interval **60**, retries 1. Save, then copy its **Push URL** (looks like `https://status.openlightnodes.org/api/push/XXXXXXXX`).
2. **TCP monitor** — New Monitor → Type **TCP Port** → host `zebra.openlightnodes.org`, port `443`, interval 60. (Kuma tracks cert expiry on this automatically.)

## Step 5 — Wire the health script (feeds the Push monitor)

On the monitor box, place `deploy/health-push.sh`, make it executable, and run it every minute with the push URL from Step 4:

```bash
sudo install -m755 health-push.sh /usr/local/bin/health-push.sh
# test once:
PUSH_URL='https://status.openlightnodes.org/api/push/XXXXXXXX' /usr/local/bin/health-push.sh && echo ok

# schedule every 60s via cron:
( crontab -l 2>/dev/null; echo "* * * * * PUSH_URL='https://status.openlightnodes.org/api/push/XXXXXXXX' /usr/local/bin/health-push.sh" ) | crontab -
```

The script reports **up** with `height N (lag k)` when serving and within `MAX_LAG` blocks of the tip, and **down** when unreachable or lagging. Adjust `MAX_LAG` if 5 is too strict.

## Step 6 — Build the public status page

Kuma UI → **Status Pages** → New:
- Title: `Open Light Nodes — Status`, slug `status` (or set it as the domain root).
- Add a **group** named `Mumbai · in`, and add both monitors (Push + TCP) to it.
- Enable "Show powered by" off if you like, set the theme, and **publish**.
- Optionally map the status page to the domain root so `status.openlightnodes.org` shows it directly.

Add the status page link to your repo README and the forum thread.

## Automating the provisioning

[`deploy/monitor-userdata.sh`](../deploy/monitor-userdata.sh) is cloud-init for
the monitor box. It performs steps 1 to 3 unattended: Docker, jq and grpcurl,
Uptime Kuma on `127.0.0.1:3001`, and Caddy with the Caddyfile above.

It deliberately leaves Caddy **stopped and disabled**, because starting it before
the DNS record resolves wastes Let's Encrypt failure attempts, and because
exposing port 443 before the Kuma admin account exists would let a passing
visitor claim admin. Create the admin over an SSH tunnel first:

```bash
ssh -i <key>.pem -L 3001:127.0.0.1:3001 ubuntu@<elastic-ip>
# then open http://127.0.0.1:3001 and create the admin user
```

Once DNS resolves and admin is set, enable TLS:

```bash
sudo systemctl enable --now caddy
sudo journalctl -u caddy -f    # expect "certificate obtained successfully"
```

## Maintenance

- The monitor box costs ~$8/mo (t3.micro) — small, but keep the Budget alert in mind.
- When you add a region, provision the node, add one Push + one TCP monitor, and add a new group to the status page.
- Uptime Kuma keeps outage history automatically — that's the "public history of degraded service" wallet teams asked for.