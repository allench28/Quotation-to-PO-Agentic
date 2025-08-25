@echo off
setlocal enabledelayedexpansion
echo 🚀 AI Quotation Processor - Final Deployment (us-east-2)
echo ========================================================

set PROJECT_NAME=quotation-processor-final
set REGION=us-east-2

REM Get AWS Account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i

REM Create timestamp
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -command "[int][double]::Parse((Get-Date -UFormat %%s))"') do set TIMESTAMP=%%i

echo 📦 Step 1/5: Backend Infrastructure
echo ===================================

REM Create DynamoDB table
aws dynamodb create-table --table-name %PROJECT_NAME%-quotations --attribute-definitions AttributeName=quotation_id,AttributeType=S --key-schema AttributeName=quotation_id,KeyType=HASH --billing-mode PAY_PER_REQUEST --region %REGION% 2>nul

REM Create S3 buckets
set DOCS_BUCKET=%PROJECT_NAME%-docs-!TIMESTAMP!
set WEB_BUCKET=%PROJECT_NAME%-web-!TIMESTAMP!

aws s3 mb s3://!DOCS_BUCKET! --region %REGION%
aws s3 mb s3://!WEB_BUCKET! --region %REGION%

REM Make both buckets public
aws s3api put-public-access-block --bucket !DOCS_BUCKET! --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" --region %REGION%
aws s3api put-bucket-policy --bucket !DOCS_BUCKET! --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicReadGetObject\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::!DOCS_BUCKET!/*\"}]}" --region %REGION%

aws s3api put-public-access-block --bucket !WEB_BUCKET! --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" --region %REGION%
aws s3api put-bucket-policy --bucket !WEB_BUCKET! --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicReadGetObject\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::!WEB_BUCKET!/*\"}]}" --region %REGION%

REM Create IAM role
aws iam create-role --role-name %PROJECT_NAME%-role --assume-role-policy-document file://lambda-trust-policy.json 2>nul
aws iam put-role-policy --role-name %PROJECT_NAME%-role --policy-name %PROJECT_NAME%-policy --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"dynamodb:PutItem\",\"dynamodb:GetItem\",\"bedrock:InvokeModel\",\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"}]}"

timeout /t 15 /nobreak >nul

echo 📚 Step 2/5: Lambda Layer for PDF Generation
echo =============================================

REM Create Lambda layer with PDF dependencies
mkdir lambda-layer && cd lambda-layer && mkdir python && cd python
pip install fpdf2==2.7.6 fontTools==4.47.0 Pillow==10.1.0 defusedxml -t . --quiet
cd .. && powershell -ExecutionPolicy Bypass -command "Compress-Archive -Path python -DestinationPath ../pdf-layer.zip -Force" && cd ..

for /f "tokens=*" %%i in ('aws lambda publish-layer-version --layer-name %PROJECT_NAME%-pdf-layer --zip-file fileb://pdf-layer.zip --compatible-runtimes python3.11 --region %REGION% --query "LayerVersionArn" --output text') do set LAYER_ARN=%%i

rmdir /s /q lambda-layer && del pdf-layer.zip

echo ⚡ Step 3/5: Lambda Function
echo ============================

REM Create Lambda function
cd backend
powershell -ExecutionPolicy Bypass -command "Compress-Archive -Path document_processor.py,simple_reports.py -DestinationPath ../lambda-function.zip -Force"
cd ..

aws lambda create-function --function-name %PROJECT_NAME%-processor --runtime python3.11 --role arn:aws:iam::!AWS_ACCOUNT_ID!:role/%PROJECT_NAME%-role --handler document_processor.handler --zip-file fileb://lambda-function.zip --timeout 300 --environment Variables="{DYNAMODB_TABLE=%PROJECT_NAME%-quotations,S3_BUCKET=!DOCS_BUCKET!}" --layers !LAYER_ARN! --region %REGION%

del lambda-function.zip

echo 🌐 Step 4/5: API Gateway with CORS
echo ==================================

REM Create API Gateway
for /f "tokens=*" %%i in ('aws apigateway create-rest-api --name %PROJECT_NAME%-api --region %REGION% --query "id" --output text') do set API_ID=%%i

for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id !API_ID! --region %REGION% --query "items[0].id" --output text') do set ROOT_ID=%%i

for /f "tokens=*" %%i in ('aws apigateway create-resource --rest-api-id !API_ID! --parent-id !ROOT_ID! --path-part upload --region %REGION% --query "id" --output text') do set RESOURCE_ID=%%i

REM Setup POST method
aws apigateway put-method --rest-api-id !API_ID! --resource-id !RESOURCE_ID! --http-method POST --authorization-type NONE --region %REGION%
aws apigateway put-integration --rest-api-id !API_ID! --resource-id !RESOURCE_ID! --http-method POST --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:%REGION%:lambda:path/2015-03-31/functions/arn:aws:lambda:%REGION%:!AWS_ACCOUNT_ID!:function:%PROJECT_NAME%-processor/invocations --region %REGION%

REM Setup CORS
aws apigateway put-method --rest-api-id !API_ID! --resource-id !RESOURCE_ID! --http-method OPTIONS --authorization-type NONE --region %REGION%
aws apigateway put-integration --rest-api-id !API_ID! --resource-id !RESOURCE_ID! --http-method OPTIONS --type MOCK --request-templates "{\"application/json\":\"{\\\"statusCode\\\": 200}\"}" --region %REGION%
aws apigateway put-method-response --rest-api-id !API_ID! --resource-id !RESOURCE_ID! --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":false,\"method.response.header.Access-Control-Allow-Methods\":false,\"method.response.header.Access-Control-Allow-Origin\":false}" --region %REGION%
aws apigateway put-integration-response --rest-api-id !API_ID! --resource-id !RESOURCE_ID! --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":\"'Content-Type'\",\"method.response.header.Access-Control-Allow-Methods\":\"'GET,POST,OPTIONS'\",\"method.response.header.Access-Control-Allow-Origin\":\"'*'\"}" --region %REGION%

REM Add Lambda permission and deploy
aws lambda add-permission --function-name %PROJECT_NAME%-processor --statement-id api-gateway-invoke-!TIMESTAMP! --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:%REGION%:!AWS_ACCOUNT_ID!:!API_ID!/*/*" --region %REGION%
aws apigateway create-deployment --rest-api-id !API_ID! --stage-name prod --region %REGION%

set API_ENDPOINT=https://!API_ID!.execute-api.%REGION%.amazonaws.com/prod/upload

echo 🎨 Step 5/5: Frontend Deployment
echo =================================

REM Update frontend with API endpoint
powershell -ExecutionPolicy Bypass -command "(Get-Content frontend/index.html) -replace 'YOUR_API_GATEWAY_ENDPOINT', '!API_ENDPOINT!' | Set-Content frontend/index.html"

REM Upload frontend
aws s3 sync frontend/ s3://!WEB_BUCKET!/

REM Create CloudFront distribution
echo {"CallerReference":"!TIMESTAMP!","Comment":"%PROJECT_NAME% frontend","DefaultRootObject":"index.html","Origins":{"Quantity":1,"Items":[{"Id":"S3-!WEB_BUCKET!","DomainName":"!WEB_BUCKET!.s3.%REGION%.amazonaws.com","CustomOriginConfig":{"HTTPPort":80,"HTTPSPort":443,"OriginProtocolPolicy":"https-only"}}]},"DefaultCacheBehavior":{"TargetOriginId":"S3-!WEB_BUCKET!","ViewerProtocolPolicy":"redirect-to-https","TrustedSigners":{"Enabled":false,"Quantity":0},"ForwardedValues":{"QueryString":false,"Cookies":{"Forward":"none"}},"MinTTL":0,"Compress":true},"Enabled":true,"PriceClass":"PriceClass_100"} > cf-config.json

for /f "tokens=*" %%i in ('aws cloudfront create-distribution --distribution-config file://cf-config.json --query "Distribution.DomainName" --output text') do set CLOUDFRONT_DOMAIN=%%i

del cf-config.json

echo 🎉 DEPLOYMENT COMPLETE!
echo =======================
echo 🌐 CloudFront URL: https://!CLOUDFRONT_DOMAIN!
echo ⚡ API Gateway URL: !API_ENDPOINT!
echo 📦 S3 Website URL: https://!WEB_BUCKET!.s3.%REGION%.amazonaws.com/index.html
echo 📊 DynamoDB Table: %PROJECT_NAME%-quotations
echo 🗄️ Documents Bucket: !DOCS_BUCKET!
echo 🌍 Region: %REGION%
echo.
echo ✅ Features:
echo • PDF/Word document upload and processing
echo • AI-powered data extraction using Bedrock Claude 3 Haiku
echo • Automatic purchase order generation
echo • PDF report generation with download links
echo • Data storage in DynamoDB
echo • CORS-enabled API Gateway
echo • CloudFront CDN distribution
echo.
echo 🚀 Your AI Quotation Processor is ready!
pause