@echo off
echo 📊 Viewing CloudWatch Logs
echo =========================

set REGION=us-east-2

echo 1. Lambda Function Logs:
echo ------------------------
aws lambda list-functions --region %REGION% --output table
echo.
echo Enter Lambda function name to view logs:
set /p FUNCTION_NAME="Function name: "
if not "%FUNCTION_NAME%"=="" (
    echo Viewing logs for: %FUNCTION_NAME%
    aws logs tail "/aws/lambda/%FUNCTION_NAME%" --region %REGION% --since 1h --format short
)

echo.
echo 2. API Gateway Logs:
echo --------------------
aws apigateway get-rest-apis --region %REGION% --output table
echo.
echo Enter API Gateway ID to view logs:
set /p API_ID="API ID: "
if not "%API_ID%"=="" (
    echo Viewing logs for API: %API_ID%
    aws logs tail "API-Gateway-Execution-Logs_%API_ID%/prod" --region %REGION% --since 1h --format short 2>nul
)

pause