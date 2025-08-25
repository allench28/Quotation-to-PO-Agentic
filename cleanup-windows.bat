@echo off
echo 🧹 Cleaning up previous deployment...
echo ===================================

set PROJECT_NAME=quotation-processor
set REGION=us-east-2

REM Get AWS Account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i

echo Cleaning up Lambda function...
aws lambda delete-function --function-name %PROJECT_NAME%-processor --region %REGION% >nul 2>&1

echo Cleaning up API Gateway...
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --query "items[?name==''%PROJECT_NAME%-api''].id" --output text --region %REGION%') do (
    if not "%%i"=="" (
        aws apigateway delete-rest-api --rest-api-id %%i --region %REGION% >nul 2>&1
    )
)

echo Cleaning up CloudFront distributions...
for /f "tokens=*" %%i in ('aws cloudfront list-distributions --query "DistributionList.Items[?Comment==''%PROJECT_NAME% frontend''].Id" --output text') do (
    if not "%%i"=="" (
        aws cloudfront get-distribution-config --id %%i --query "DistributionConfig" --output json > temp-dist-config.json 2>nul
        if exist temp-dist-config.json (
            powershell -command "(Get-Content temp-dist-config.json | ConvertFrom-Json) | ForEach-Object { $_.Enabled = $false } | ConvertTo-Json -Depth 10" > temp-dist-disabled.json
            aws cloudfront update-distribution --id %%i --distribution-config file://temp-dist-disabled.json --if-match * >nul 2>&1
            timeout /t 30 /nobreak >nul
            aws cloudfront delete-distribution --id %%i --if-match * >nul 2>&1
            del temp-dist-config.json temp-dist-disabled.json >nul 2>&1
        )
    )
)

echo Cleaning up S3 buckets...
for /f "tokens=*" %%i in ('aws s3 ls ^| findstr "%PROJECT_NAME%"') do (
    set BUCKET_LINE=%%i
    for /f "tokens=3" %%j in ("!BUCKET_LINE!") do (
        echo Deleting bucket: %%j
        aws s3 rm s3://%%j --recursive >nul 2>&1
        aws s3 rb s3://%%j >nul 2>&1
    )
)

echo Cleaning up DynamoDB table...
aws dynamodb delete-table --table-name %PROJECT_NAME%-quotations --region %REGION% >nul 2>&1

echo Cleaning up IAM role...
aws iam delete-role-policy --role-name %PROJECT_NAME%-role --policy-name %PROJECT_NAME%-policy >nul 2>&1
aws iam delete-role-policy --role-name %PROJECT_NAME%-role --policy-name bedrock-prompt-policy >nul 2>&1
aws iam delete-role --role-name %PROJECT_NAME%-role >nul 2>&1

echo Cleaning up Bedrock prompts...
for /f "tokens=*" %%i in ('aws bedrock-agent list-prompts --query "promptSummaries[?name==''%PROJECT_NAME%-prompt''].id" --output text --region %REGION%') do (
    if not "%%i"=="" (
        aws bedrock-agent delete-prompt --prompt-identifier %%i --region %REGION% >nul 2>&1
    )
)

echo Cleaning up Lambda layers...
aws lambda delete-layer-version --layer-name fpdf-layer --version-number 1 --region %REGION% >nul 2>&1

echo ✅ Cleanup complete!
echo Waiting 30 seconds for AWS resources to be fully deleted...
timeout /t 30 /nobreak >nul
echo Ready for fresh deployment.