@echo off
echo 🧹 Complete Cleanup - All Regions
echo =================================

set PROJECT_NAME=quotation-processor

echo Cleaning up us-east-1...
aws lambda delete-function --function-name %PROJECT_NAME%-processor --region us-east-1 2>nul
aws dynamodb delete-table --table-name %PROJECT_NAME%-quotations --region us-east-1 2>nul
aws iam delete-role-policy --role-name %PROJECT_NAME%-role --policy-name %PROJECT_NAME%-policy 2>nul
aws iam delete-role --role-name %PROJECT_NAME%-role 2>nul

for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region us-east-1 --query "items[?contains(name,''quotation-processor'')].id" --output text') do (
    if not "%%i"=="" aws apigateway delete-rest-api --rest-api-id %%i --region us-east-1 2>nul
)

for /f "tokens=3" %%i in ('aws s3 ls ^| findstr "quotation-processor"') do (
    aws s3 rm s3://%%i --recursive 2>nul
    aws s3 rb s3://%%i 2>nul
)

echo Cleaning up us-east-2...
aws lambda delete-function --function-name %PROJECT_NAME%-processor --region us-east-2 2>nul
aws dynamodb delete-table --table-name %PROJECT_NAME%-quotations --region us-east-2 2>nul

for /f "tokens=*" %%i in ('aws apigateway get-rest-apis --region us-east-2 --query "items[?contains(name,''quotation-processor'')].id" --output text') do (
    if not "%%i"=="" aws apigateway delete-rest-api --rest-api-id %%i --region us-east-2 2>nul
)

for /f "tokens=*" %%i in ('aws bedrock-agent list-prompts --region us-east-1 --query "promptSummaries[?contains(name,''quotation-processor'')].id" --output text') do (
    if not "%%i"=="" aws bedrock-agent delete-prompt --prompt-identifier %%i --region us-east-1 2>nul
)

for /f "tokens=*" %%i in ('aws bedrock-agent list-prompts --region us-east-2 --query "promptSummaries[?contains(name,''quotation-processor'')].id" --output text') do (
    if not "%%i"=="" aws bedrock-agent delete-prompt --prompt-identifier %%i --region us-east-2 2>nul
)

echo Cleaning up CloudFront distributions...
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

echo Cleaning up east2 resources...
aws lambda delete-function --function-name quotation-processor-east2-processor --region us-east-2 2>nul
aws dynamodb delete-table --table-name quotation-processor-east2-quotations --region us-east-2 2>nul

echo ✅ Cleanup complete! Waiting 60 seconds...
timeout /t 60 /nobreak >nul
echo Ready for fresh deployment in us-east-2