@echo off
setlocal enabledelayedexpansion
echo 🚀 Deploy with Lambda Function URL (No API Gateway)
echo ==================================================

set PROJECT_NAME=quotation-processor-east2
set REGION=us-east-2

REM Get AWS Account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i

REM Create timestamp
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -command "[int][double]::Parse((Get-Date -UFormat %%s))"') do set TIMESTAMP=%%i

echo 📦 Step 1/3: Creating Backend Infrastructure...
echo ================================================

REM Create DynamoDB table
aws dynamodb create-table --table-name %PROJECT_NAME%-quotations --attribute-definitions AttributeName=quotation_id,AttributeType=S --key-schema AttributeName=quotation_id,KeyType=HASH --billing-mode PAY_PER_REQUEST --region %REGION% 2>nul

REM Create S3 buckets
set DOCS_BUCKET=%PROJECT_NAME%-docs-!TIMESTAMP!
set WEB_BUCKET=%PROJECT_NAME%-web-!TIMESTAMP!

aws s3 mb s3://!DOCS_BUCKET! --region %REGION%
aws s3 mb s3://!WEB_BUCKET! --region %REGION%

REM Make S3 bucket public
aws s3api put-public-access-block --bucket !WEB_BUCKET! --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" --region %REGION%
aws s3api put-bucket-policy --bucket !WEB_BUCKET! --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicReadGetObject\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::!WEB_BUCKET!/*\"}]}" --region %REGION%

REM Create IAM role
aws iam create-role --role-name %PROJECT_NAME%-role --assume-role-policy-document file://lambda-trust-policy.json 2>nul
aws iam put-role-policy --role-name %PROJECT_NAME%-role --policy-name %PROJECT_NAME%-policy --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"dynamodb:PutItem\",\"dynamodb:GetItem\",\"bedrock:InvokeModel\",\"bedrock:GetPrompt\",\"bedrock-agent:GetPrompt\",\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"}]}"

timeout /t 15 /nobreak >nul

REM Create Lambda function
cd backend
powershell -ExecutionPolicy Bypass -command "Compress-Archive -Path document_processor.py,simple_reports.py,requirements.txt -DestinationPath ../lambda-function.zip -Force"
cd ..

aws lambda create-function --function-name %PROJECT_NAME%-processor --runtime python3.11 --role arn:aws:iam::!AWS_ACCOUNT_ID!:role/%PROJECT_NAME%-role --handler document_processor.handler --zip-file fileb://lambda-function.zip --timeout 300 --environment Variables="{DYNAMODB_TABLE=%PROJECT_NAME%-quotations,S3_BUCKET=!DOCS_BUCKET!}" --region %REGION%

del lambda-function.zip

echo 🌐 Step 2/3: Creating Lambda Function URL...
echo =============================================

REM Create Lambda Function URL with CORS
aws lambda create-function-url-config --function-name %PROJECT_NAME%-processor --cors "{\"AllowCredentials\":false,\"AllowHeaders\":[\"content-type\",\"x-amz-date\",\"authorization\",\"x-api-key\",\"x-amz-security-token\",\"x-amz-user-agent\"],\"AllowMethods\":[\"GET\",\"POST\",\"OPTIONS\"],\"AllowOrigins\":[\"*\"],\"ExposeHeaders\":[\"date\",\"keep-alive\"],\"MaxAge\":86400}" --auth-type NONE --region %REGION%

REM Get Function URL
for /f "tokens=*" %%i in ('aws lambda get-function-url-config --function-name %PROJECT_NAME%-processor --query "FunctionUrl" --output text --region %REGION%') do set FUNCTION_URL=%%i

echo Function URL: !FUNCTION_URL!

echo 🎨 Step 3/3: Deploying Frontend...
echo ==================================

REM Update frontend with Function URL
powershell -ExecutionPolicy Bypass -command "(Get-Content frontend/index.html) -replace 'YOUR_API_GATEWAY_ENDPOINT', '!FUNCTION_URL!' | Set-Content frontend/index.html"

REM Upload frontend
aws s3 sync frontend/ s3://!WEB_BUCKET!/

REM Create CloudFront distribution
echo {"CallerReference":"!TIMESTAMP!","Comment":"%PROJECT_NAME% frontend","DefaultRootObject":"index.html","Origins":{"Quantity":1,"Items":[{"Id":"S3-!WEB_BUCKET!","DomainName":"!WEB_BUCKET!.s3.%REGION%.amazonaws.com","CustomOriginConfig":{"HTTPPort":80,"HTTPSPort":443,"OriginProtocolPolicy":"https-only"}}]},"DefaultCacheBehavior":{"TargetOriginId":"S3-!WEB_BUCKET!","ViewerProtocolPolicy":"redirect-to-https","TrustedSigners":{"Enabled":false,"Quantity":0},"ForwardedValues":{"QueryString":false,"Cookies":{"Forward":"none"}},"MinTTL":0,"Compress":true},"Enabled":true,"PriceClass":"PriceClass_100"} > cf-config.json

for /f "tokens=*" %%i in ('aws cloudfront create-distribution --distribution-config file://cf-config.json --query "Distribution.DomainName" --output text') do set CLOUDFRONT_DOMAIN=%%i

del cf-config.json

echo 🎉 DEPLOYMENT COMPLETE!
echo =======================
echo 🌐 CloudFront URL: https://!CLOUDFRONT_DOMAIN!
echo ⚡ Lambda Function URL: !FUNCTION_URL!
echo 📦 S3 Direct URL: https://!WEB_BUCKET!.s3.%REGION%.amazonaws.com/index.html
echo 📊 DynamoDB Table: %PROJECT_NAME%-quotations
echo 🗄️ Documents Bucket: !DOCS_BUCKET!
echo 🌍 Region: %REGION%
echo.
echo ✅ No CORS issues - Lambda Function URL handles CORS automatically!
pause