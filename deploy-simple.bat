@echo off
echo 🚀 Simple AI Quotation Processor Deployment
echo ===========================================

set PROJECT_NAME=quotation-processor
set REGION=us-east-2

REM Get AWS Account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i

REM Create S3 buckets with timestamp
for /f %%i in ('powershell -ExecutionPolicy Bypass -command "Get-Date -UFormat %%s"') do set TIMESTAMP=%%i
set DOCS_BUCKET=%PROJECT_NAME%-docs-%TIMESTAMP%
set WEB_BUCKET=%PROJECT_NAME%-web-%TIMESTAMP%

echo Creating S3 buckets...
aws s3 mb s3://%DOCS_BUCKET% --region %REGION%
aws s3 mb s3://%WEB_BUCKET% --region %REGION%

echo Updating Lambda function...
cd backend
powershell -ExecutionPolicy Bypass -command "Compress-Archive -Path document_processor.py,simple_reports.py,requirements.txt -DestinationPath ../lambda-update.zip -Force"
cd ..

aws lambda update-function-code --function-name %PROJECT_NAME%-processor --zip-file fileb://lambda-update.zip --region %REGION%
aws lambda update-function-configuration --function-name %PROJECT_NAME%-processor --environment Variables="{DYNAMODB_TABLE=%PROJECT_NAME%-quotations,S3_BUCKET=%DOCS_BUCKET%}" --region %REGION%

del lambda-update.zip

echo Uploading frontend...
aws s3 sync frontend/ s3://%WEB_BUCKET%/
aws s3 website s3://%WEB_BUCKET% --index-document index.html

echo Creating API Gateway...
for /f "tokens=*" %%i in ('aws apigateway create-rest-api --name %PROJECT_NAME%-api-%TIMESTAMP% --region %REGION% --query "id" --output text') do set API_ID=%%i

for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id %API_ID% --region %REGION% --query "items[0].id" --output text') do set ROOT_ID=%%i

for /f "tokens=*" %%i in ('aws apigateway create-resource --rest-api-id %API_ID% --parent-id %ROOT_ID% --path-part upload --region %REGION% --query "id" --output text') do set RESOURCE_ID=%%i

aws apigateway put-method --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method POST --authorization-type NONE --region %REGION%

aws apigateway put-integration --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method POST --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:%REGION%:lambda:path/2015-03-31/functions/arn:aws:lambda:%REGION%:%AWS_ACCOUNT_ID%:function:%PROJECT_NAME%-processor/invocations --region %REGION%

aws lambda add-permission --function-name %PROJECT_NAME%-processor --statement-id api-gateway-invoke-%TIMESTAMP% --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:%REGION%:%AWS_ACCOUNT_ID%:%API_ID%/*/*" --region %REGION%

aws apigateway create-deployment --rest-api-id %API_ID% --stage-name prod --region %REGION%

set API_ENDPOINT=https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod

echo Updating frontend with API endpoint...
powershell -ExecutionPolicy Bypass -command "(Get-Content frontend/index.html) -replace 'YOUR_API_GATEWAY_ENDPOINT', '%API_ENDPOINT%' | Set-Content frontend/index.html"
aws s3 sync frontend/ s3://%WEB_BUCKET%/

echo Creating CloudFront distribution...
echo {"CallerReference":"%TIMESTAMP%","Comment":"quotation-processor frontend","DefaultRootObject":"index.html","Origins":{"Quantity":1,"Items":[{"Id":"S3-%WEB_BUCKET%","DomainName":"%WEB_BUCKET%.s3.amazonaws.com","S3OriginConfig":{"OriginAccessIdentity":""}}]},"DefaultCacheBehavior":{"TargetOriginId":"S3-%WEB_BUCKET%","ViewerProtocolPolicy":"redirect-to-https","TrustedSigners":{"Enabled":false,"Quantity":0},"ForwardedValues":{"QueryString":false,"Cookies":{"Forward":"none"}},"MinTTL":0,"Compress":true},"Enabled":true,"PriceClass":"PriceClass_100"} > cf-config.json

for /f "tokens=*" %%i in ('aws cloudfront create-distribution --distribution-config file://cf-config.json --query "Distribution.DomainName" --output text') do set CLOUDFRONT_DOMAIN=%%i

del cf-config.json

echo.
echo 🎉 DEPLOYMENT COMPLETE!
echo =======================
echo 🌐 CloudFront URL: https://%CLOUDFRONT_DOMAIN%
echo 🔗 API Gateway URL: %API_ENDPOINT%
echo 📦 S3 Website URL: http://%WEB_BUCKET%.s3-website-%REGION%.amazonaws.com
echo.
echo 📋 RESOURCES:
echo =============
echo Lambda Function: %PROJECT_NAME%-processor (updated)
echo Documents Bucket: %DOCS_BUCKET%
echo Web Bucket: %WEB_BUCKET%
echo API Gateway ID: %API_ID%
echo Region: %REGION%
echo.
pause