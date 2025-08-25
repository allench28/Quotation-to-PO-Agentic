@echo off
echo 📊 Enabling API Gateway Detailed Logging
echo ========================================

set REGION=us-east-2

REM Get API Gateway ID
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[?contains(name,''quotation-processor'')].id" --output text') do set API_ID=%%i

if "%API_ID%"=="" (
    echo No API Gateway found
    exit /b 1
)

echo API Gateway ID: %API_ID%

REM Create CloudWatch log group for API Gateway
aws logs create-log-group --log-group-name "API-Gateway-Execution-Logs_%API_ID%/prod" --region %REGION% 2>nul

REM Enable detailed logging
echo Enabling detailed logging...
aws apigateway update-stage ^
  --rest-api-id %API_ID% ^
  --stage-name prod ^
  --patch-ops op=replace,path=/*/logging/loglevel,value=INFO ^
  --region %REGION%

aws apigateway update-stage ^
  --rest-api-id %API_ID% ^
  --stage-name prod ^
  --patch-ops op=replace,path=/*/logging/dataTrace,value=true ^
  --region %REGION%

aws apigateway update-stage ^
  --rest-api-id %API_ID% ^
  --stage-name prod ^
  --patch-ops op=replace,path=/accessLogSettings/destinationArn,value=arn:aws:logs:%REGION%:954986424675:log-group:API-Gateway-Execution-Logs_%API_ID%/prod ^
  --region %REGION%

aws apigateway update-stage ^
  --rest-api-id %API_ID% ^
  --stage-name prod ^
  --patch-ops op=replace,path=/accessLogSettings/format,value="$requestId $ip $caller $user [$requestTime] \"$httpMethod $resourcePath $protocol\" $status $error.message $error.messageString" ^
  --region %REGION%

echo ✅ API Gateway logging enabled!
echo Log group: API-Gateway-Execution-Logs_%API_ID%/prod
echo.
echo Now test your application and then run: view-logs.bat

pause