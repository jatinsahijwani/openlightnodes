# Contributing

Thanks for your interest. This project only works if other people run nodes, so
contributions of every size are welcome.

## Adding your node to the network

This is the most valuable contribution. Bring up an endpoint using
[RUN-A-NODE.md](./RUN-A-NODE.md), then open a pull request adding a row to the
endpoints table in [README.md](./README.md) with your endpoint, region, backend,
and operator handle.

Please confirm in the pull request that:

- client IP addresses and wallet addresses are not logged,
- TLS is valid and issued for your domain,
- the node is at the chain tip.

## Reporting problems

Open an issue. For a broken or degraded endpoint, include the endpoint name, the
time in UTC, and what you observed. The output of a `GetLightdInfo` call is
usually enough:

```
grpcurl -authority <domain> <ip>:443 \
  cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo
```

Please do not include your own IP address or any wallet addresses in an issue.

## Code and documentation changes

- Keep pull requests focused on one thing. Small and reviewable beats large.
- Shell scripts should pass `shellcheck` and keep the existing style: `set -euo
  pipefail`, comments explaining why rather than what.
- Anything that touches AWS should be safe by default. Nothing destructive
  without an explicit confirmation step.
- If you change a documented number in the benchmark report, say how you
  measured it so someone else can repeat it.

## Security

Please do not open a public issue for a security problem. Email the address on
the maintainer's GitHub profile with the details and give a reasonable window
for a fix before disclosing.

## Scope

The aim is many independent operators on many providers, not one central
service. Contributions that increase provider, region, or operator diversity are
especially welcome. Anything that would turn this into a single point of control
is out of scope.
