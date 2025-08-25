@echo off
echo 🧪 Testing API Gateway Configuration
echo ===================================

set REGION=us-east-2

REM Get API Gateway ID
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[?contains(name,''quotation-processor'')].id" --output text') do set API_ID=%%i

if "%API_ID%"=="" (
    echo No API Gateway found
    exit /b 1
)

echo API Gateway ID: %API_ID%
set API_URL=https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload

echo Testing OPTIONS request (CORS preflight):
curl -X OPTIONS %API_URL% -H "Origin: https://example.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: Content-Type" -v

echo.
echo Testing simple GET request:
curl -X GET %API_URL% -v

echo.
echo API Gateway Methods:
aws apigateway get-resource --rest-api-id %API_ID% --resource-id $(aws apigateway get-resources --rest-api-id %API_ID% --region %REGION% --query "items[?pathPart=='upload'].id" --output text) --region %REGION%

pause