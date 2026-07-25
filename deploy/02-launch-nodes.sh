#!/usr/bin/env bash
# 02-launch-nodes.sh — launch the two Zcash nodes in ap-south-1 (Mumbai).
#   - node A: full Zebra + Zaino     (t3.xlarge, 300 GB gp3)
#   - node B: Zakura pruned + Zaino  (t3.large,   60 GB gp3)
# Creates a key pair + a security group locked to YOUR current public IP for SSH.
# Public ports opened: 443 (TLS endpoint via Caddy) and 8233 (Zebra P2P). gRPC stays local.
set -euo pipefail

REGION="${REGION:-ap-south-1}"
KEY_NAME="${KEY_NAME:-zcash-asia}"
SG_NAME="${SG_NAME:-zcash-node-sg}"
PROJECT_TAG="zcash-asia-nodes"

echo "== Launching Zcash nodes in $REGION =="

# --- latest Ubuntu 22.04 AMI (region-correct, no hardcoded IDs) ---
# Prefer the SSM public parameter; fall back to querying Canonical's AMIs directly,
# because ssm:GetParameters is denied for this IAM user.
AMI=$(aws ssm get-parameters --region "$REGION" \
  --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
  --query 'Parameters[0].Value' --output text 2>/dev/null) || AMI=""
if [ -z "$AMI" ] || [ "$AMI" = "None" ]; then
  echo "SSM lookup unavailable — resolving via describe-images (owner: Canonical)."
  AMI=$(aws ec2 describe-images --region "$REGION" --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' \
              'Name=state,Values=available' \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
fi
[ -n "$AMI" ] && [ "$AMI" != "None" ] || { echo "Could not resolve an Ubuntu 22.04 AMI in $REGION"; exit 1; }
echo "Ubuntu 22.04 AMI: $AMI"

# --- key pair (create + save private key if missing) ---
if ! aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Creating key pair $KEY_NAME (saving to ./$KEY_NAME.pem)"
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_NAME.pem"
  chmod 400 "$KEY_NAME.pem"
else
  echo "Key pair $KEY_NAME already exists (using it). Ensure you have $KEY_NAME.pem locally."
fi

# --- security group locked to your current public IP for SSH ---
MYIP=$(curl -s https://checkip.amazonaws.com)
echo "Your public IP for SSH allow-list: $MYIP"
if ! SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
      --group-names "$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null); then
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
      --query 'Vpcs[0].VpcId' --output text)
  SG_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
      --description "Zcash light client nodes" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
      --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=$MYIP/32,Description=ssh-me}]" >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
      --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[{CidrIp=0.0.0.0/0,Description=tls-endpoint}]" >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
      --ip-permissions IpProtocol=tcp,FromPort=8233,ToPort=8233,IpRanges="[{CidrIp=0.0.0.0/0,Description=zebra-p2p}]" >/dev/null
  echo "Created security group $SG_ID"
else
  echo "Using existing security group $SG_ID (verify port 22 is allowed from $MYIP)."
fi

launch () {
  local NAME=$1 ITYPE=$2 DISK=$3 UDATA=$4
  echo "Launching $NAME ($ITYPE, ${DISK}GB)..."
  aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI" --instance-type "$ITYPE" --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --credit-specification CpuCredits=unlimited \
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
    --user-data "file://$UDATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=$PROJECT_TAG}]" \
    --query 'Instances[0].InstanceId' --output text
}

HERE="$(cd "$(dirname "$0")" && pwd)"
ZEBRA_ID=$(launch "zcash-zebra-mumbai"  t3.xlarge 300 "$HERE/zebra-userdata.sh")
ZAKURA_ID=$(launch "zcash-zakura-mumbai" t3.large  60  "$HERE/zakura-userdata.sh")

echo "Waiting for instances to enter 'running'..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$ZEBRA_ID" "$ZAKURA_ID"

echo
echo "== Nodes launched =="
aws ec2 describe-instances --region "$REGION" --instance-ids "$ZEBRA_ID" "$ZAKURA_ID" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,IP:PublicIpAddress,State:State.Name}' \
  --output table

ZEBRA_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ZEBRA_ID"  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ZAKURA_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ZAKURA_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo
echo "SSH in (give cloud-init ~2–3 min to install Docker first):"
echo "  ssh -i $KEY_NAME.pem ubuntu@$ZEBRA_IP     # Zebra box  -> cat /root/NEXT_STEPS.md"
echo "  ssh -i $KEY_NAME.pem ubuntu@$ZAKURA_IP    # Zakura box -> cat /root/NEXT_STEPS.md"
echo
echo "Reminder: these bill ~\$8/day combined. Stop them once benchmarking is done."
