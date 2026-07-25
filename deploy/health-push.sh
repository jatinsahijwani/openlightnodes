#!/usr/bin/env bash
# health-push.sh — checks an Open Light Nodes endpoint and pushes the result to
# an Uptime Kuma "Push" monitor. Run every ~60s from the MONITORING box (not the
# node box) so it exercises the real public path.
#
# Requires: grpcurl, jq, curl.  The endpoint must have gRPC server reflection on
# (lightwalletd does) and a valid TLS cert on :443.
set -uo pipefail

HOST="${HOST:-zebra.openlightnodes.org}"      # endpoint domain
ENDPOINT="${HOST}:443"
PUSH_URL="${PUSH_URL:?set PUSH_URL to your Kuma push URL, e.g. https://status.openlightnodes.org/api/push/XXXX}"
MAX_LAG="${MAX_LAG:-5}"                        # blocks behind tip before we call it degraded
METHOD="cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo"

start=$(date +%s%3N)
INFO=$(grpcurl "$ENDPOINT" "$METHOD" 2>/dev/null); rc=$?
end=$(date +%s%3N); ms=$((end-start))

if [ $rc -ne 0 ] || [ -z "$INFO" ]; then
  curl -fsS "${PUSH_URL}?status=down&msg=grpc_unreachable" >/dev/null 2>&1
  exit 0
fi

BH=$(echo "$INFO" | jq -r '.blockHeight // empty')
EH=$(echo "$INFO" | jq -r '.estimatedHeight // empty')
if [ -z "$BH" ] || [ -z "$EH" ]; then
  curl -fsS "${PUSH_URL}?status=down&msg=bad_response" >/dev/null 2>&1
  exit 0
fi

lag=$(( EH - BH ))
if [ "$lag" -le "$MAX_LAG" ]; then
  curl -fsS "${PUSH_URL}?status=up&msg=height%20${BH}%20(lag%20${lag})&ping=${ms}" >/dev/null 2>&1
else
  curl -fsS "${PUSH_URL}?status=down&msg=lagging%20${lag}%20blocks%20(height%20${BH})&ping=${ms}" >/dev/null 2>&1
fi