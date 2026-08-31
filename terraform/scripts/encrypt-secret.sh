#!/bin/bash
set -e

PROFILE="${AWS_PROFILE:-quick-poc-admin}"
KMS_ALIAS="alias/quick-mcp-poc-ssm"

# -r: preserve backslashes (e.g. \n in JSON private keys)
# -s: hide input
echo -n "Enter secret value: " && read -rs SECRET_VALUE && echo

ENCRYPTED=$(aws kms encrypt \
  --key-id ${KMS_ALIAS} \
  --plaintext fileb://<(echo -n "$SECRET_VALUE") \
  --output text \
  --query CiphertextBlob \
  --profile ${PROFILE})

echo "Encrypted value:"
echo "$ENCRYPTED"
