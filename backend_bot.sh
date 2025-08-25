#!/bin/bash

echo "Setting up AI Quotation Processor Backend..."

PROJECT_NAME="quotation-processor"
REGION="us-east-1"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "1. Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name ${PROJECT_NAME}-quotations \
    --attribute-definitions AttributeName=quotation_id,AttributeType=S \
    --key-schema AttributeName=quotation_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION || echo "DynamoDB table already exists"

echo "2. Creating S3 buckets..."
DOCS_BUCKET="${PROJECT_NAME}-docs-$(date +%s)"
WEB_BUCKET="${PROJECT_NAME}-web-$(date +%s)"

aws s3 mb s3://$DOCS_BUCKET --region $REGION
aws s3 mb s3://$WEB_BUCKET --region $REGION

echo "3. Creating IAM role..."
aws iam create-role \
    --role-name ${PROJECT_NAME}-role \
    --assume-role-policy-document file://lambda-trust-policy.json || echo "IAM role already exists"

echo "4. Attaching policies..."
aws iam put-role-policy \
    --role-name ${PROJECT_NAME}-role \
    --policy-name ${PROJECT_NAME}-policy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "bedrock:InvokeModel",
                    "bedrock:GetPrompt",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            }
        ]
    }'

echo "5. Creating Lambda layer..."
aws lambda publish-layer-version \
    --layer-name fpdf-layer \
    --description "FPDF and dependencies for PDF generation" \
    --compatible-runtimes python3.11 \
    --region $REGION || echo "Layer already exists"

echo "6. Creating Lambda function..."
cd backend
zip -r ../lambda-function.zip document_processor.py simple_reports.py requirements.txt
cd ..

LAYER_ARN=$(aws lambda list-layer-versions --layer-name fpdf-layer --query 'LayerVersions[0].LayerVersionArn' --output text --region $REGION)

aws lambda create-function \
    --function-name ${PROJECT_NAME}-processor \
    --runtime python3.11 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-role \
    --handler document_processor.handler \
    --zip-file fileb://lambda-function.zip \
    --timeout 300 \
    --layers $LAYER_ARN \
    --environment Variables="{DYNAMODB_TABLE=${PROJECT_NAME}-quotations,S3_BUCKET=$DOCS_BUCKET}" \
    --region $REGION

rm lambda-function.zip

echo "DOCS_BUCKET=$DOCS_BUCKET" > .env
echo "WEB_BUCKET=$WEB_BUCKET" >> .env

echo "Backend setup complete!"
echo "Lambda Function: ${PROJECT_NAME}-processor"
echo "DynamoDB Table: ${PROJECT_NAME}-quotations"
echo "S3 Buckets: $DOCS_BUCKET, $WEB_BUCKET"