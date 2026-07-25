#!/usr/bin/env bash
# 00-preflight.sh — READ ONLY. Confirms your AWS setup. Changes nothing.
set -euo pipefail

REGION="${REGION:-ap-south-1}"     # Mumbai
echo "== Zcash node deploy :: preflight =="
echo "Region: $REGION"
echo

echo "-- Who am I (caller identity) --"
aws sts get-caller-identity --output table

echo
echo "-- CLI / region sanity --"
aws configure list || true

echo
echo "-- Running instances in $REGION (review these before Step 1) --"
aws ec2 describe-instances --region "$REGION" \
  --filters "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,State:State.Name,AZ:Placement.AvailabilityZone,Launched:LaunchTime,PublicIP:PublicIpAddress}' \
  --output table

echo
echo "-- EBS volumes (what storage exists / could be deleted on terminate) --"
aws ec2 describe-volumes --region "$REGION" \
  --query 'Volumes[].{VolumeID:VolumeId,Size:Size,State:State,Attached:Attachments[0].InstanceId,DeleteOnTerm:Attachments[0].DeleteOnTermination}' \
  --output table

echo
echo "-- Cost visibility (may be denied if no Budgets/Billing perms; that's OK) --"
ACCT="$(aws sts get-caller-identity --query Account --output text)"
aws budgets describe-budgets --account-id "$ACCT" --output table 2>/dev/null \
  || echo "  (No Budgets access — set a billing alarm in the console: Billing > Budgets.)"

echo
echo "Preflight done. Nothing was changed. Review the tables above, then run 01-list-and-cleanup.sh."
