#!/bin/bash

awslocal dynamodb create-table \
  --region ap-northeast-1 \
  --table-name quick-mcp-poc-users \
  --attribute-definitions AttributeName=PK,AttributeType=S \
  --key-schema AttributeName=PK,KeyType=HASH \
  --billing-mode PROVISIONED \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
