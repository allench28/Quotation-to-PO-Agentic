@echo off
echo 📊 Checking CloudWatch Logs
echo ===========================

set REGION=us-east-2

echo Lambda Function Logs:
echo ---------------------
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/quotation-processor" --region %REGION% --query "logGroups[].logGroupName" --output text

echo.
echo API Gateway Logs:
echo -----------------
aws logs describe-log-groups --log-group-name-prefix "API-Gateway-Execution-Logs" --region %REGION% --query "logGroups[].logGroupName" --output text

echo.
echo Recent Lambda Logs:
echo ------------------
for /f "tokens=*" %%i in ('aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/quotation-processor" --region %REGION% --query "logGroups[0].logGroupName" --output text') do (
    if not "%%i"=="None" (
        echo Log Group: %%i
        aws logs tail "%%i" --region %REGION% --since 10m
    )
)

echo.
echo Recent API Gateway Logs:
echo ------------------------
for /f "tokens=*" %%i in ('aws logs describe-log-groups --log-group-name-prefix "API-Gateway-Execution-Logs" --region %REGION% --query "logGroups[0].logGroupName" --output text') do (
    if not "%%i"=="None" (
        echo Log Group: %%i
        aws logs tail "%%i" --region %REGION% --since 10m
    )
)

pause