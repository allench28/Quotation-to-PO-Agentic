@echo off
echo 🧪 Testing CORS Configuration
echo =============================

set REGION=us-east-2

REM Get API Gateway ID
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[?contains(name,''quotation-processor'')].id" --output text') do set API_ID=%%i

if "%API_ID%"=="" (
    echo No API Gateway found
    exit /b 1
)

echo API Gateway ID: %API_ID%
set API_URL=https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload

echo.
echo 1. Testing OPTIONS request (CORS preflight):
echo --------------------------------------------
curl -X OPTIONS "%API_URL%" ^
  -H "Origin: https://example.com" ^
  -H "Access-Control-Request-Method: POST" ^
  -H "Access-Control-Request-Headers: Content-Type" ^
  -v

echo.
echo 2. Testing POST request:
echo -----------------------
curl -X POST "%API_URL%" ^
  -H "Content-Type: application/json" ^
  -H "Origin: https://example.com" ^
  -d "{\"test\":\"data\"}" ^
  -v

echo.
echo 3. API Gateway Resource Configuration:
echo -------------------------------------
aws apigateway get-resources --rest-api-id %API_ID% --region %REGION%

echo.
echo 4. Upload Resource Methods:
echo --------------------------
for /f "tokens=*" %%i in ('aws apigateway get-resources --rest-api-id %API_ID% --region %REGION% --query "items[?pathPart==''upload''].id" --output text') do (
    echo Resource ID: %%i
    aws apigateway get-resource --rest-api-id %API_ID% --resource-id %%i --region %REGION%
)

pause