#!/bin/bash

echo "Setting up CloudFront Distribution..."

PROJECT_NAME="quotation-processor"
REGION="us-east-1"

# Load environment variables
source .env 2>/dev/null || {
    echo "Error: .env file not found. Run backend_bot.sh first."
    exit 1
}

if [ -z "$WEB_BUCKET" ]; then
    echo "Error: WEB_BUCKET not set. Run backend_bot.sh first."
    exit 1
fi

echo "1. Uploading frontend files..."
aws s3 sync frontend/ s3://$WEB_BUCKET/
aws s3 website s3://$WEB_BUCKET --index-document index.html

echo "2. Creating CloudFront distribution..."
DISTRIBUTION_CONFIG='{
    "CallerReference": "'$(date +%s)'",
    "Comment": "'${PROJECT_NAME}' frontend distribution",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-'$WEB_BUCKET'",
                "DomainName": "'$WEB_BUCKET'.s3.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-'$WEB_BUCKET'",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "MinTTL": 0,
        "Compress": true
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}'

DISTRIBUTION_ID=$(aws cloudfront create-distribution \
    --distribution-config "$DISTRIBUTION_CONFIG" \
    --query 'Distribution.Id' --output text)

CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
    --id $DISTRIBUTION_ID \
    --query 'Distribution.DomainName' --output text)

echo "3. Creating API Gateway..."
API_ID=$(aws apigateway create-rest-api \
    --name ${PROJECT_NAME}-api \
    --region $REGION \
    --query 'id' --output text)

ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --region $REGION \
    --query 'items[0].id' --output text)

RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_ID \
    --path-part upload \
    --region $REGION \
    --query 'id' --output text)

aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region $REGION

aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${REGION}:$(aws sts get-caller-identity --query Account --output text):function:${PROJECT_NAME}-processor/invocations \
    --region $REGION

aws lambda add-permission \
    --function-name ${PROJECT_NAME}-processor \
    --statement-id api-gateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --region $REGION

aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name prod \
    --region $REGION

API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod"

echo "CloudFront setup complete!"
echo "CloudFront URL: https://$CLOUDFRONT_DOMAIN"
echo "API Gateway URL: $API_ENDPOINT"
echo "S3 Website URL: http://$WEB_BUCKET.s3-website-$REGION.amazonaws.com"