@echo off
echo 📊 Quick Log Check
echo ==================

set REGION=us-east-2

echo Lambda Functions:
aws lambda list-functions --region %REGION% --query "Functions[].FunctionName" --output text

echo.
echo API Gateways:
aws apigateway get-rest-apis --region %REGION% --query "items[].{Name:name,Id:id}" --output table

echo.
echo Log Groups:
aws logs describe-log-groups --region %REGION% --query "logGroups[?contains(logGroupName,'quotation') || contains(logGroupName,'API-Gateway')].logGroupName" --output text

echo.
echo Recent Lambda Logs (last 10 minutes):
aws logs filter-log-events --region %REGION% --log-group-name "/aws/lambda/quotation-processor-east2-processor" --start-time %~1 --query "events[].message" --output text 2>nul

echo.
echo Recent API Gateway Logs (if any):
for /f %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[0].id" --output text') do (
    aws logs filter-log-events --region %REGION% --log-group-name "API-Gateway-Execution-Logs_%%i/prod" --start-time %~1 --query "events[].message" --output text 2>nul
)

pause