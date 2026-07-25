# Roadmap

Deliberately modest and ship-first. Real, running infrastructure appears early and can be evaluated by the community and wallet teams before anything larger is proposed.

## Phase 1 — Foundation ✅ (in progress)

- [x] First archive endpoint live: `zebra.openlightnodes.org:443` (Mumbai)
- [x] Zebra + lightwalletd, TLS via Caddy, no client-IP logging
- [x] Reproducible benchmark: Zebra archive vs Zakura pruned ([report](./benchmark-report.md))
- [x] Open-source deploy scripts
- [x] Public status page ([status.openlightnodes.org](https://status.openlightnodes.org)), health and uptime by region, on a host separate from the nodes
- [ ] Second region

## Phase 2 — Operators and hardening

- [ ] Onboard the first independent community operators (see [RUN-A-NODE.md](./RUN-A-NODE.md))
- [ ] Public node/health map of participating operators
- [ ] Stricter privacy defaults documented; Tor hidden service
- [ ] Monitoring, alerting, and incident-response runbooks
- [ ] Move to Zaino once it supports the current node value pools (tracking upstream)

## Phase 3 — Ecosystem integration and resilience

- [ ] Comprehensive wallet-integration docs; coordinate test integrations
- [ ] One-command / appliance-friendly self-hosting packages
- [ ] R&D toward decentralized endpoint discovery, in coordination with core teams (not a new central service)
- [ ] Sustainability and long-term maintenance plan

## Open questions we're actively seeking input on

- Best path for health-aware endpoint selection that stays decentralized.
- Whether endpoint discovery belongs in tooling, in wallets, or eventually in the protocol.
- What benchmarks matter most to node providers and wallet teams.

Feedback welcome on the [forum thread](https://forum.zcashcommunity.com/t/56727) or via issues.
