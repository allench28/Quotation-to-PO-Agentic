#!/bin/bash

echo "Setting up Bedrock Knowledge Base and Prompt Management..."

PROJECT_NAME="quotation-processor"
REGION="us-east-1"

echo "1. Creating Bedrock managed prompt..."
aws bedrock-agent create-prompt \
    --name "${PROJECT_NAME}-prompt" \
    --description "Enhanced quotation data extraction with advanced prompt engineering" \
    --variants file://enhanced-prompt.json \
    --region $REGION

echo "2. Creating prompt version..."
PROMPT_ID=$(aws bedrock-agent list-prompts \
    --query "promptSummaries[?name=='${PROJECT_NAME}-prompt'].id" \
    --output text --region $REGION)

aws bedrock-agent create-prompt-version \
    --prompt-identifier $PROMPT_ID \
    --description "Production version for quotation processing" \
    --region $REGION

echo "3. Updating Lambda permissions for Bedrock..."
aws iam put-role-policy \
    --role-name ${PROJECT_NAME}-role \
    --policy-name bedrock-prompt-policy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "bedrock:InvokeModel",
                    "bedrock:GetPrompt",
                    "bedrock-agent:GetPrompt"
                ],
                "Resource": "*"
            }
        ]
    }'

echo "Bedrock setup complete!"
echo "Prompt ID: $PROMPT_ID"
echo "Model: Claude 3 Sonnet"