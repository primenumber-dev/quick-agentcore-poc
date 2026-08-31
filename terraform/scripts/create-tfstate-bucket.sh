#!/bin/bash
set -e

BUCKET_NAME="terraform.tfstate.professional-services-quick-poc"
PROFILE="${AWS_PROFILE:-quick-poc-admin}"
REGION="ap-northeast-1"

echo "========================================="
echo "Bucket Name: ${BUCKET_NAME}"
echo "AWS Profile: ${PROFILE}"
echo "Region:      ${REGION}"
echo "========================================="

echo "Checking if bucket already exists..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --profile ${PROFILE} 2>/dev/null; then
  echo "Bucket ${BUCKET_NAME} already exists!"
else
  echo "Creating bucket..."
  aws s3api create-bucket \
    --bucket ${BUCKET_NAME} \
    --region ${REGION} \
    --create-bucket-configuration LocationConstraint=${REGION} \
    --profile ${PROFILE}
fi

echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket ${BUCKET_NAME} \
  --versioning-configuration Status=Enabled \
  --profile ${PROFILE}

echo "Configuring encryption..."
aws s3api put-bucket-encryption \
  --bucket ${BUCKET_NAME} \
  --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }' \
  --profile ${PROFILE}

echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket ${BUCKET_NAME} \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile ${PROFILE}

echo ""
echo "S3 bucket created successfully!"
