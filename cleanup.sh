#!/bin/bash
set -e

echo "🧹 AI Quotation Processor - Resource Cleanup"
echo "============================================="

PROJECT_NAME="quotation-processor-final"
REGION="us-east-1"
AWS_PROFILE="gikensakata"

# Set AWS profile for all commands
export AWS_PROFILE=$AWS_PROFILE
echo "Using AWS Profile: $AWS_PROFILE"

echo "⚠️  WARNING: This will delete ALL resources created by deploy-final.sh"
echo "This includes S3 buckets, Lambda functions, API Gateway, CloudFront, DynamoDB, and IAM roles."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo ""
echo "🗑️  Step 1/6: Disable CloudFront Distributions"
echo "=============================================="

# Get all CloudFront distributions with our project name
DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='${PROJECT_NAME} frontend'].Id" --output text --region ${REGION} --no-cli-pager 2>/dev/null || true)

if [ ! -z "$DISTRIBUTIONS" ]; then
    for DIST_ID in $DISTRIBUTIONS; do
        echo "Disabling CloudFront distribution: $DIST_ID"
        # Get current config
        aws cloudfront get-distribution-config --id $DIST_ID --query 'DistributionConfig' --output json > temp-dist-config.json
        # Disable distribution
        sed -i.bak 's/"Enabled": true/"Enabled": false/' temp-dist-config.json
        ETAG=$(aws cloudfront get-distribution-config --id $DIST_ID --query 'ETag' --output text)
        aws cloudfront update-distribution --id $DIST_ID --distribution-config file://temp-dist-config.json --if-match $ETAG --no-cli-pager
        rm temp-dist-config.json temp-dist-config.json.bak
        echo "Distribution $DIST_ID disabled (manual deletion required later)"
    done
else
    echo "No CloudFront distributions found"
fi

echo ""
echo "🗑️  Step 2/6: Delete API Gateway"
echo "================================"

API_IDS=$(aws apigateway get-rest-apis --query "items[?name=='${PROJECT_NAME}-api'].id" --output text --region ${REGION} --no-cli-pager 2>/dev/null || true)

if [ ! -z "$API_IDS" ]; then
    for API_ID in $API_IDS; do
        echo "Deleting API Gateway: $API_ID"
        aws apigateway delete-rest-api --rest-api-id $API_ID --region ${REGION} --no-cli-pager
    done
else
    echo "No API Gateway found"
fi

echo ""
echo "🗑️  Step 3/6: Delete Lambda Function and Layer"
echo "==============================================="

# Delete Lambda function
echo "Deleting Lambda function: ${PROJECT_NAME}-processor"
aws lambda delete-function --function-name ${PROJECT_NAME}-processor --region ${REGION} --no-cli-pager 2>/dev/null || echo "Lambda function not found"

# Delete Lambda layer (all versions)
LAYER_VERSIONS=$(aws lambda list-layer-versions --layer-name ${PROJECT_NAME}-pdf-layer --query 'LayerVersions[].Version' --output text --region ${REGION} --no-cli-pager 2>/dev/null || true)

if [ ! -z "$LAYER_VERSIONS" ]; then
    for VERSION in $LAYER_VERSIONS; do
        echo "Deleting Lambda layer version: ${PROJECT_NAME}-pdf-layer:$VERSION"
        aws lambda delete-layer-version --layer-name ${PROJECT_NAME}-pdf-layer --version-number $VERSION --region ${REGION} --no-cli-pager 2>/dev/null || true
    done
else
    echo "No Lambda layer versions found"
fi

echo ""
echo "🗑️  Step 4/6: Delete S3 Buckets"
echo "================================"

# Find and delete all project S3 buckets
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${PROJECT_NAME}')].Name" --output text --region ${REGION} --no-cli-pager 2>/dev/null || true)

if [ ! -z "$BUCKETS" ]; then
    for BUCKET in $BUCKETS; do
        echo "Emptying S3 bucket: $BUCKET"
        aws s3 rm s3://$BUCKET --recursive --region ${REGION} 2>/dev/null || true
        echo "Deleting S3 bucket: $BUCKET"
        aws s3api delete-bucket --bucket $BUCKET --region ${REGION} 2>/dev/null || true
    done
else
    echo "No S3 buckets found"
fi

echo ""
echo "🗑️  Step 5/6: Delete DynamoDB Table"
echo "==================================="

echo "Deleting DynamoDB table: ${PROJECT_NAME}-quotations"
aws dynamodb delete-table --table-name ${PROJECT_NAME}-quotations --region ${REGION} --no-cli-pager 2>/dev/null || echo "DynamoDB table not found"

echo ""
echo "🗑️  Step 6/6: Delete IAM Role and Policies"
echo "==========================================="

# Delete role policy first
echo "Deleting IAM role policy: ${PROJECT_NAME}-policy"
aws iam delete-role-policy --role-name ${PROJECT_NAME}-role --policy-name ${PROJECT_NAME}-policy 2>/dev/null || echo "IAM role policy not found"

# Delete role
echo "Deleting IAM role: ${PROJECT_NAME}-role"
aws iam delete-role --role-name ${PROJECT_NAME}-role 2>/dev/null || echo "IAM role not found"

echo ""
echo "✅ CLEANUP COMPLETE!"
echo "===================="
echo "Resources cleaned up:"
echo "• CloudFront distributions (disabled only)"
echo "• API Gateway (deleted)"
echo "• Lambda function and layer (deleted)"
echo "• S3 buckets (emptied and deleted)"
echo "• DynamoDB table (deleted)"
echo "• IAM role and policies (deleted)"
echo ""
echo "ℹ️  Note: CloudFront distributions are disabled but not deleted"
echo "🚀 You can now run deploy-final.sh to create fresh resources"