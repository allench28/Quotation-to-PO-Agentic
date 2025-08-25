@echo off
echo 🧹 Complete Cleanup of Previous Deployment
echo ==========================================

set PROJECT_NAME=quotation-processor
set REGION=us-east-2

REM Get AWS Account ID
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i

echo Deleting Lambda function...
aws lambda delete-function --function-name %PROJECT_NAME%-processor --region %REGION% 2>nul

echo Deleting API Gateways...
for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region %REGION% --query "items[?contains(name,''quotation-processor'')].id" --output text') do (
    if not "%%i"=="" (
        echo Deleting API Gateway: %%i
        aws apigateway delete-rest-api --rest-api-id %%i --region %REGION% 2>nul
    )
)

echo Deleting S3 buckets...
for /f "tokens=3" %%i in ('aws s3 ls ^| findstr "quotation-processor"') do (
    echo Deleting bucket: %%i
    aws s3 rm s3://%%i --recursive 2>nul
    aws s3 rb s3://%%i 2>nul
)

echo Deleting DynamoDB table...
aws dynamodb delete-table --table-name %PROJECT_NAME%-quotations --region %REGION% 2>nul

echo Deleting IAM role policies...
aws iam delete-role-policy --role-name %PROJECT_NAME%-role --policy-name %PROJECT_NAME%-policy 2>nul
aws iam delete-role-policy --role-name %PROJECT_NAME%-role --policy-name bedrock-prompt-policy 2>nul

echo Deleting IAM role...
aws iam delete-role --role-name %PROJECT_NAME%-role 2>nul

echo Deleting CloudFront distributions...
for /f "tokens=*" %%i in ('aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment,''quotation-processor'')].Id" --output text') do (
    if not "%%i"=="" (
        echo Disabling CloudFront distribution: %%i
        aws cloudfront get-distribution-config --id %%i --query "DistributionConfig" > temp-config.json 2>nul
        if exist temp-config.json (
            powershell -ExecutionPolicy Bypass -command "(Get-Content temp-config.json | ConvertFrom-Json) | ForEach-Object { $_.Enabled = $false } | ConvertTo-Json -Depth 10" > temp-disabled.json
            for /f "tokens=*" %%j in ('aws cloudfront get-distribution --id %%i --query "ETag" --output text') do (
                aws cloudfront update-distribution --id %%i --distribution-config file://temp-disabled.json --if-match %%j 2>nul
            )
            del temp-config.json temp-disabled.json 2>nul
        )
    )
)

echo Deleting Bedrock prompts...
for /f "tokens=*" %%i in ('aws bedrock-agent list-prompts --region %REGION% --query "promptSummaries[?contains(name,''quotation-processor'')].id" --output text') do (
    if not "%%i"=="" (
        echo Deleting Bedrock prompt: %%i
        aws bedrock-agent delete-prompt --prompt-identifier %%i --region %REGION% 2>nul
    )
)

echo Deleting Lambda layers...
aws lambda delete-layer-version --layer-name fpdf-layer --version-number 1 --region %REGION% 2>nul

echo ✅ Cleanup complete!
echo Waiting 60 seconds for AWS resources to be fully deleted...
timeout /t 60 /nobreak >nul

echo 🚀 Ready for fresh deployment!
echo Run: deploy-windows.bat