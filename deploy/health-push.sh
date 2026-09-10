#!/usr/bin/env bash
# health-push.sh — checks an Open Light Nodes endpoint and pushes the result to
# an Uptime Kuma "Push" monitor. Run every ~60s from the MONITORING box (not the
# node box) so it exercises the real public path.
#
# Requires: grpcurl, jq, curl.  The endpoint must have gRPC server reflection on
# (lightwalletd does) and a valid TLS cert on :443.
#
# Two checks, and the second one is load-bearing. GetLightdInfo's blockHeight and
# estimatedHeight are both reported from the *backend node* (zebra), so they stay
# at the chain tip even when lightwalletd's own ingester is wedged and cannot
# serve a single block. That is not hypothetical: NU6.3 activated at block
# 3428143 and lightwalletd v0.4.19 could not parse the new ZIP-229 coinbase
# format, so this endpoint served nothing for ~6 weeks while the lag check stayed
# green. So we also ask for an actual block and require real data back.
set -uo pipefail

HOST="${HOST:-zebra.openlightnodes.org}"      # endpoint domain
ENDPOINT="${HOST}:443"
PUSH_URL="${PUSH_URL:?set PUSH_URL to your Kuma push URL, e.g. https://status.openlightnodes.org/api/push/XXXX}"
MAX_LAG="${MAX_LAG:-5}"                        # blocks behind tip before we call it degraded
SERVE_DEPTH="${SERVE_DEPTH:-10}"               # how far below tip to request a block (avoids reorg edge)
METHOD="cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo"
GETBLOCK="cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlock"

push() { curl -fsS "${PUSH_URL}?$1" >/dev/null 2>&1; }

start=$(date +%s%3N)
INFO=$(grpcurl "$ENDPOINT" "$METHOD" 2>/dev/null); rc=$?
end=$(date +%s%3N); ms=$((end-start))

if [ $rc -ne 0 ] || [ -z "$INFO" ]; then
  push "status=down&msg=grpc_unreachable"
  exit 0
fi

BH=$(echo "$INFO" | jq -r '.blockHeight // empty')
EH=$(echo "$INFO" | jq -r '.estimatedHeight // empty')
if [ -z "$BH" ] || [ -z "$EH" ]; then
  push "status=down&msg=bad_response"
  exit 0
fi

lag=$(( EH - BH ))
if [ "$lag" -gt "$MAX_LAG" ]; then
  push "status=down&msg=lagging%20${lag}%20blocks%20(height%20${BH})&ping=${ms}"
  exit 0
fi

# Can it actually serve a block? A wedged ingester fails here while the lag
# check above still reads as healthy.
probe=$(( BH - SERVE_DEPTH ))
BLOCK=$(grpcurl -d "{\"height\":${probe}}" "$ENDPOINT" "$GETBLOCK" 2>/dev/null); brc=$?
GOT=$(echo "$BLOCK" | jq -r '.height // empty' 2>/dev/null)

if [ $brc -ne 0 ] || [ "$GOT" != "$probe" ]; then
  push "status=down&msg=cannot%20serve%20blocks%20at%20${probe}%20(info%20height%20${BH})&ping=${ms}"
  exit 0
fi

push "status=up&msg=height%20${BH}%20(lag%20${lag},%20served%20${probe})&ping=${ms}"
