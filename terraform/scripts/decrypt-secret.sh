#!/bin/bash
set -e

PROFILE="${AWS_PROFILE:-quick-poc-admin}"

echo -n "Enter encrypted value: " && read ENCRYPTED_VALUE && echo

aws kms decrypt \
  --ciphertext-blob fileb://<(echo -n "$ENCRYPTED_VALUE" | base64 --decode) \
  --output text \
  --query Plaintext \
  --profile ${PROFILE} | base64 --decode

echo ""
