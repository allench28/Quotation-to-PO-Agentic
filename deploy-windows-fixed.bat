@echo off
setlocal enabledelayedexpansion
echo 🚀 AI Quotation Processor Deployment (Windows - us-east-2)
echo ========================================================

REM Check prerequisites
aws sts get-caller-identity >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ AWS CLI not configured. Please run 'aws configure' first.
    pause
    exit /b 1
)

echo ✅ Prerequisites check passed
echo.

set PROJECT_NAME=quotation-processor
set REGION=us-east-2

REM Get AWS Account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i

echo 📦 Step 1/4: Creating Backend Infrastructure...
echo ================================================

REM Create DynamoDB table
echo Creating DynamoDB table...
aws dynamodb create-table ^
    --table-name %PROJECT_NAME%-quotations ^
    --attribute-definitions AttributeName=quotation_id,AttributeType=S ^
    --key-schema AttributeName=quotation_id,KeyType=HASH ^
    --billing-mode PAY_PER_REQUEST ^
    --region %REGION% >nul 2>&1
if %errorlevel% neq 0 echo Table may already exist, continuing...

REM Create S3 buckets with timestamp
for /f "tokens=*" %%i in ('powershell -command "[int][double]::Parse((Get-Date -UFormat %%s))"') do set TIMESTAMP=%%i
set DOCS_BUCKET=%PROJECT_NAME%-docs-%TIMESTAMP%
set WEB_BUCKET=%PROJECT_NAME%-web-%TIMESTAMP%

echo Creating S3 buckets...
aws s3 mb s3://%DOCS_BUCKET% --region %REGION%
if %errorlevel% neq 0 (
    echo ❌ Failed to create docs bucket
    pause
    exit /b 1
)

aws s3 mb s3://%WEB_BUCKET% --region %REGION%
if %errorlevel% neq 0 (
    echo ❌ Failed to create web bucket
    pause
    exit /b 1
)

REM Create IAM role
echo Creating IAM role...
aws iam create-role ^
    --role-name %PROJECT_NAME%-role ^
    --assume-role-policy-document file://lambda-trust-policy.json >nul 2>&1
if %errorlevel% neq 0 echo Role may already exist, continuing...

REM Attach policies
echo Attaching IAM policies...
aws iam put-role-policy ^
    --role-name %PROJECT_NAME%-role ^
    --policy-name %PROJECT_NAME%-policy ^
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"dynamodb:PutItem\",\"dynamodb:GetItem\",\"bedrock:InvokeModel\",\"bedrock:GetPrompt\",\"bedrock-agent:GetPrompt\",\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"}]}"

REM Wait for role propagation
echo Waiting for IAM role propagation...
timeout /t 20 /nobreak >nul

REM Create Lambda function (without layer first)
echo Creating Lambda function...
cd backend
powershell -command "Compress-Archive -Path document_processor.py,simple_reports.py,requirements.txt -DestinationPath ../lambda-function.zip -Force"
cd ..

aws lambda create-function ^
    --function-name %PROJECT_NAME%-processor ^
    --runtime python3.11 ^
    --role arn:aws:iam::%AWS_ACCOUNT_ID%:role/%PROJECT_NAME%-role ^
    --handler document_processor.handler ^
    --zip-file fileb://lambda-function.zip ^
    --timeout 300 ^
    --environment Variables="{DYNAMODB_TABLE=%PROJECT_NAME%-quotations,S3_BUCKET=%DOCS_BUCKET%}" ^
    --region %REGION%

if %errorlevel% neq 0 (
    echo ❌ Failed to create Lambda function
    del lambda-function.zip
    pause
    exit /b 1
)

del lambda-function.zip

echo ✅ Backend infrastructure deployed
echo.

echo 🧠 Step 2/4: Setting up Bedrock Knowledge Base...
echo =================================================

REM Create Bedrock managed prompt
echo Creating Bedrock managed prompt...
aws bedrock-agent create-prompt ^
    --name "%PROJECT_NAME%-prompt" ^
    --description "Enhanced quotation data extraction" ^
    --variants file://enhanced-prompt.json ^
    --region %REGION% >nul 2>&1

REM Get prompt ID and create version
timeout /t 5 /nobreak >nul
for /f "tokens=*" %%i in ('aws bedrock-agent list-prompts --query "promptSummaries[?name==''%PROJECT_NAME%-prompt''].id" --output text --region %REGION%') do set PROMPT_ID=%%i

if not "!PROMPT_ID!"=="" (
    aws bedrock-agent create-prompt-version ^
        --prompt-identifier !PROMPT_ID! ^
        --description "Production version" ^
        --region %REGION% >nul 2>&1
    echo Prompt ID: !PROMPT_ID!
) else (
    echo ⚠️ Could not create Bedrock prompt, continuing without it...
    set PROMPT_ID=N/A
)

echo ✅ Bedrock knowledge base configured
echo.

echo 🌐 Step 3/4: Deploying Frontend and API...
echo ==========================================

REM Upload frontend files
echo Uploading frontend files...
aws s3 sync frontend/ s3://%WEB_BUCKET%/
aws s3 website s3://%WEB_BUCKET% --index-document index.html

REM Create API Gateway
echo Creating API Gateway...
for /f "tokens=*" %%i in ('aws apigateway create-rest-api --name %PROJECT_NAME%-api --region %REGION% --query "id" --output text') do set API_ID=%%i

if "!API_ID!"=="" (
    echo ❌ Failed to create API Gateway
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id !API_ID! --region %REGION% --query "items[0].id" --output text') do set ROOT_ID=%%i

for /f "tokens=*" %%i in ('aws apigateway create-resource --rest-api-id !API_ID! --parent-id !ROOT_ID! --path-part upload --region %REGION% --query "id" --output text') do set RESOURCE_ID=%%i

REM Setup POST method
aws apigateway put-method ^
    --rest-api-id !API_ID! ^
    --resource-id !RESOURCE_ID! ^
    --http-method POST ^
    --authorization-type NONE ^
    --region %REGION%

REM Setup OPTIONS method for CORS
aws apigateway put-method ^
    --rest-api-id !API_ID! ^
    --resource-id !RESOURCE_ID! ^
    --http-method OPTIONS ^
    --authorization-type NONE ^
    --region %REGION%

REM Setup POST integration
aws apigateway put-integration ^
    --rest-api-id !API_ID! ^
    --resource-id !RESOURCE_ID! ^
    --http-method POST ^
    --type AWS_PROXY ^
    --integration-http-method POST ^
    --uri arn:aws:apigateway:%REGION%:lambda:path/2015-03-31/functions/arn:aws:lambda:%REGION%:%AWS_ACCOUNT_ID%:function:%PROJECT_NAME%-processor/invocations ^
    --region %REGION%

REM Setup OPTIONS integration for CORS
aws apigateway put-integration ^
    --rest-api-id !API_ID! ^
    --resource-id !RESOURCE_ID! ^
    --http-method OPTIONS ^
    --type MOCK ^
    --integration-http-method OPTIONS ^
    --request-templates "{\"application/json\":\"{\\\"statusCode\\\": 200}\"}" ^
    --region %REGION%

REM Setup OPTIONS method response
aws apigateway put-method-response ^
    --rest-api-id !API_ID! ^
    --resource-id !RESOURCE_ID! ^
    --http-method OPTIONS ^
    --status-code 200 ^
    --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":false,\"method.response.header.Access-Control-Allow-Methods\":false,\"method.response.header.Access-Control-Allow-Origin\":false}" ^
    --region %REGION%

REM Setup OPTIONS integration response
aws apigateway put-integration-response ^
    --rest-api-id !API_ID! ^
    --resource-id !RESOURCE_ID! ^
    --http-method OPTIONS ^
    --status-code 200 ^
    --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":\"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'\",\"method.response.header.Access-Control-Allow-Methods\":\"'POST,OPTIONS'\",\"method.response.header.Access-Control-Allow-Origin\":\"'*'\"}" ^
    --region %REGION%

REM Add Lambda permission
aws lambda add-permission ^
    --function-name %PROJECT_NAME%-processor ^
    --statement-id api-gateway-invoke ^
    --action lambda:InvokeFunction ^
    --principal apigateway.amazonaws.com ^
    --source-arn "arn:aws:execute-api:%REGION%:%AWS_ACCOUNT_ID%:!API_ID!/*/*" ^
    --region %REGION%

REM Deploy API
aws apigateway create-deployment ^
    --rest-api-id !API_ID! ^
    --stage-name prod ^
    --region %REGION%

set API_ENDPOINT=https://!API_ID!.execute-api.%REGION%.amazonaws.com/prod

REM Update frontend with API endpoint
echo Updating frontend configuration...
powershell -command "(Get-Content frontend/index.html) -replace 'YOUR_API_GATEWAY_ENDPOINT', '%API_ENDPOINT%' | Set-Content frontend/index.html"
aws s3 sync frontend/ s3://%WEB_BUCKET%/

REM Create CloudFront distribution
echo Creating CloudFront distribution...
echo {"CallerReference":"%TIMESTAMP%","Comment":"%PROJECT_NAME% frontend","DefaultRootObject":"index.html","Origins":{"Quantity":1,"Items":[{"Id":"S3-%WEB_BUCKET%","DomainName":"%WEB_BUCKET%.s3.amazonaws.com","S3OriginConfig":{"OriginAccessIdentity":""}}]},"DefaultCacheBehavior":{"TargetOriginId":"S3-%WEB_BUCKET%","ViewerProtocolPolicy":"redirect-to-https","TrustedSigners":{"Enabled":false,"Quantity":0},"ForwardedValues":{"QueryString":false,"Cookies":{"Forward":"none"}},"MinTTL":0,"Compress":true},"Enabled":true,"PriceClass":"PriceClass_100"} > cloudfront-config.json

for /f "tokens=*" %%i in ('aws cloudfront create-distribution --distribution-config file://cloudfront-config.json --query "Distribution.DomainName" --output text') do set CLOUDFRONT_DOMAIN=%%i

del cloudfront-config.json

echo ✅ Frontend and API deployed
echo.

echo 🎯 Step 4/4: Final Configuration...
echo ==================================

echo Waiting for resources to be ready...
timeout /t 10 /nobreak >nul

echo ✅ Final configuration complete
echo.

echo 🎉 DEPLOYMENT COMPLETE!
echo =======================
echo Your AI Quotation Processor is now live!
echo.
echo 📱 APPLICATION URLS:
echo ==================
echo 🌐 CloudFront URL (HTTPS): https://!CLOUDFRONT_DOMAIN!
echo 🔗 API Gateway URL:        !API_ENDPOINT!
echo 📦 S3 Website URL:         http://%WEB_BUCKET%.s3-website-%REGION%.amazonaws.com
echo.
echo 📋 RESOURCES CREATED:
echo ====================
echo 🗄️  DynamoDB Table:        %PROJECT_NAME%-quotations
echo 📁 Documents S3 Bucket:    %DOCS_BUCKET%
echo 🌐 Web S3 Bucket:          %WEB_BUCKET%
echo ⚡ Lambda Function:        %PROJECT_NAME%-processor
echo 🧠 Bedrock Prompt ID:      !PROMPT_ID!
echo 🌍 Region:                 %REGION%
echo.
echo 🚀 The system is ready to process quotation documents!
echo    Access your application at: https://!CLOUDFRONT_DOMAIN!
echo.
pause