@echo off
echo 🧪 Simple API Test
echo ==================

set REGION=us-east-2

echo Getting API Gateway info...
aws apigateway get-rest-apis --region %REGION% --output table

echo.
echo Enter your API Gateway ID:
set /p API_ID="API ID: "

if "%API_ID%"=="" (
    echo No API ID provided
    pause
    exit /b 1
)

set API_URL=https://%API_ID%.execute-api.%REGION%.amazonaws.com/prod/upload

echo.
echo Testing API URL: %API_URL%
echo.

echo 1. Testing OPTIONS (CORS preflight):
curl -X OPTIONS "%API_URL%" -H "Origin: https://example.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: Content-Type" -i

echo.
echo 2. Testing simple GET:
curl -X GET "%API_URL%" -H "Origin: https://example.com" -i

echo.
echo 3. Testing POST with data:
curl -X POST "%API_URL%" -H "Content-Type: application/json" -H "Origin: https://example.com" -d "{\"test\":\"data\"}" -i

pause