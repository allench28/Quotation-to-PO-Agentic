@echo off
echo 🔧 Simple CORS Fix - Enable CORS on API Gateway
echo ===============================================

set REGION=us-east-2

REM Get API Gateway ID
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[?contains(name,''quotation-processor'')].id" --output text') do set API_ID=%%i

if "%API_ID%"=="" (
    echo No API Gateway found
    exit /b 1
)

echo Found API Gateway: %API_ID%

REM Get resource ID for /upload
for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id %API_ID% --region %REGION% --query "items[?pathPart==''upload''].id" --output text') do set RESOURCE_ID=%%i

echo Found resource: %RESOURCE_ID%

REM Enable CORS using AWS CLI built-in command
echo Enabling CORS...
aws apigateway put-method --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --authorization-type NONE --region %REGION%

aws apigateway put-integration --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --type MOCK --integration-http-method OPTIONS --request-templates "{\"application/json\":\"{\\\"statusCode\\\": 200}\"}" --region %REGION%

aws apigateway put-method-response --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":false,\"method.response.header.Access-Control-Allow-Methods\":false,\"method.response.header.Access-Control-Allow-Origin\":false}" --region %REGION%

aws apigateway put-integration-response --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":\"'Content-Type'\",\"method.response.header.Access-Control-Allow-Methods\":\"'GET,POST,OPTIONS'\",\"method.response.header.Access-Control-Allow-Origin\":\"'*'\"}" --region %REGION%

REM Deploy changes
aws apigateway create-deployment --rest-api-id %API_ID% --stage-name prod --region %REGION%

echo ✅ CORS enabled! Test URL: https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload

REM Test CORS
echo Testing CORS...
curl -X OPTIONS https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload -H "Origin: https://example.com" -v

pause