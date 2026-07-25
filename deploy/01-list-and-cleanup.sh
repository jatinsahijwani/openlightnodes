#!/usr/bin/env bash
# 01-list-and-cleanup.sh — SAFE, interactive cleanup of existing instances.
# Lists running/stopped instances, YOU pick specific IDs, choose stop vs terminate,
# and terminate requires typing a confirmation word. Nothing happens by default.
set -euo pipefail
REGION="${REGION:-ap-south-1}"

echo "== Existing instances in $REGION =="
aws ec2 describe-instances --region "$REGION" \
  --filters "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,State:State.Name,Launched:LaunchTime,PublicIP:PublicIpAddress}' \
  --output table

echo
echo "Enter the instance IDs you want to act on, separated by spaces."
echo "Leave blank and press Enter to do NOTHING and exit."
read -r -p "Instance IDs: " -a IDS

if [ "${#IDS[@]}" -eq 0 ]; then
  echo "No IDs entered. Exiting without changes."; exit 0
fi

echo
echo "You selected: ${IDS[*]}"
echo "Choose an action:"
echo "  1) STOP        (reversible — you can start these again later; storage kept)"
echo "  2) TERMINATE   (PERMANENT — destroys the instance AND its attached volumes)"
read -r -p "Action [1/2]: " ACT

case "$ACT" in
  1)
    echo "Stopping: ${IDS[*]}"
    aws ec2 stop-instances --region "$REGION" --instance-ids "${IDS[@]}" --output table
    echo "Stop requested. These can be restarted later and are no longer billed for compute."
    ;;
  2)
    echo
    echo "!!! TERMINATION IS PERMANENT AND DELETES ATTACHED STORAGE !!!"
    echo "About to terminate: ${IDS[*]}"
    read -r -p "Type exactly  TERMINATE  to proceed (anything else cancels): " CONF
    if [ "$CONF" = "TERMINATE" ]; then
      aws ec2 terminate-instances --region "$REGION" --instance-ids "${IDS[@]}" --output table
      echo "Termination requested."
    else
      echo "Cancelled. No instances were terminated."
    fi
    ;;
  *)
    echo "Unrecognized choice. No action taken."; exit 0
    ;;
esac
