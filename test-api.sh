#!/bin/bash

echo "🔍 API Gateway Test Script"
echo "=========================="

# Get the latest API Gateway
API_ID=$(aws apigateway get-rest-apis --query "items[?contains(name, 'quotation-processor-final')].id" --output text --region us-east-1)

if [ -z "$API_ID" ]; then
    echo "❌ No API Gateway found"
    exit 1
fi

API_ENDPOINT="https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod/upload"

echo "🔗 Testing API Gateway: $API_ENDPOINT"
echo ""

# Test 1: Basic connectivity
echo "Test 1: Basic connectivity (OPTIONS request)"
curl -X OPTIONS "$API_ENDPOINT" -v -H "Origin: https://example.com" 2>&1 | head -20

echo ""
echo "Test 2: POST request with test data"
curl -X POST "$API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Origin: https://example.com" \
  -d '{"test": "data"}' \
  -v 2>&1 | head -20

echo ""
echo "🔍 API Gateway Details:"
echo "API ID: $API_ID"
echo "Endpoint: $API_ENDPOINT"

# Check if Lambda function exists
LAMBDA_EXISTS=$(aws lambda get-function --function-name quotation-processor-final-processor --region us-east-1 2>/dev/null && echo "EXISTS" || echo "NOT_FOUND")
echo "Lambda Function: $LAMBDA_EXISTS"

# Check recent CloudWatch logs
echo ""
echo "📋 Recent Lambda Logs (if any):"
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/quotation-processor-final" --region us-east-1 --query "logGroups[].logGroupName" --output text 2>/dev/null || echo "No log groups found"