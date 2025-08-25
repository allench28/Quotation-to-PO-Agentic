@echo off
echo 🔧 Fixing API Gateway Configuration
echo ==================================

set REGION=us-east-2
set API_ID=w97olmmfg5

echo Using API Gateway: %API_ID%

REM Get root resource ID
for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id %API_ID% --region %REGION% --query "items[0].id" --output text') do set ROOT_ID=%%i
echo Root resource: %ROOT_ID%

REM Create upload resource
echo Creating /upload resource...
for /f "tokens=*" %%i in ('aws apigateway create-resource --rest-api-id %API_ID% --parent-id %ROOT_ID% --path-part upload --region %REGION% --query "id" --output text') do set RESOURCE_ID=%%i
echo Upload resource: %RESOURCE_ID%

REM Setup POST method
echo Setting up POST method...
aws apigateway put-method --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method POST --authorization-type NONE --region %REGION%

REM Setup POST integration
echo Setting up POST integration...
aws apigateway put-integration --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method POST --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:%REGION%:lambda:path/2015-03-31/functions/arn:aws:lambda:%REGION%:954986424675:function:quotation-processor-east2-processor/invocations --region %REGION%

REM Setup OPTIONS method for CORS
echo Setting up CORS...
aws apigateway put-method --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --authorization-type NONE --region %REGION%

aws apigateway put-integration --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --type MOCK --request-templates "{\"application/json\":\"{\\\"statusCode\\\": 200}\"}" --region %REGION%

aws apigateway put-method-response --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":false,\"method.response.header.Access-Control-Allow-Methods\":false,\"method.response.header.Access-Control-Allow-Origin\":false}" --region %REGION%

aws apigateway put-integration-response --rest-api-id %API_ID% --resource-id %RESOURCE_ID% --http-method OPTIONS --status-code 200 --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\":\"'Content-Type'\",\"method.response.header.Access-Control-Allow-Methods\":\"'GET,POST,OPTIONS'\",\"method.response.header.Access-Control-Allow-Origin\":\"'*'\"}" --region %REGION%

REM Add Lambda permission
echo Adding Lambda permission...
aws lambda add-permission --function-name quotation-processor-east2-processor --statement-id api-gateway-invoke-fix --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:%REGION%:954986424675:%API_ID%/*/*" --region %REGION%

REM Deploy API
echo Deploying API...
aws apigateway create-deployment --rest-api-id %API_ID% --stage-name prod --region %REGION%

echo ✅ API Gateway fixed!
echo Test URL: https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload

REM Test CORS
echo Testing CORS...
curl -X OPTIONS "https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload" -H "Origin: https://example.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: Content-Type" -i

pause