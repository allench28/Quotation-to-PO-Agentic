@echo off
echo 🔧 Fixing CORS for existing API Gateway
echo ======================================

set REGION=us-east-2

REM Get the API Gateway ID
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[?contains(name,''quotation-processor'')].id" --output text') do set API_ID=%%i

if "%API_ID%"=="" (
    echo No API Gateway found
    exit /b 1
)

echo Found API Gateway: %API_ID%

REM Get resource ID
for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id %API_ID% --region %REGION% --query "items[?pathPart==''upload''].id" --output text') do set RESOURCE_ID=%%i

echo Found resource: %RESOURCE_ID%

REM Delete existing OPTIONS method
aws apigateway delete-method --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --region %REGION% 2>nul

REM Create new OPTIONS method
aws apigateway put-method --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --authorization-type NONE --region %REGION%

REM Create OPTIONS integration
aws apigateway put-integration --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --type MOCK --request-templates "{\"application/json\":\"{\\\"statusCode\\\": 200}\"}" --region %REGION%

REM Create OPTIONS method response
aws apigateway put-method-response --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":false,\"method.response.header.Access-Control-Allow-Methods\":false,\"method.response.header.Access-Control-Allow-Origin\":false}" --region %REGION%

REM Create OPTIONS integration response
aws apigateway put-integration-response --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":\"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'\",\"method.response.header.Access-Control-Allow-Methods\":\"'POST,OPTIONS'\",\"method.response.header.Access-Control-Allow-Origin\":\"'*'\"}" --region %REGION%

REM Deploy the changes
aws apigateway create-deployment --rest-api-id %API_ID% --stage-name prod --region %REGION%

echo ✅ CORS fixed! API Gateway: %API_ID%
echo Test URL: https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload
pause