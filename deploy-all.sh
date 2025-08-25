#!/bin/bash

echo "🚀 Complete AI Quotation Processor Deployment"
echo "=============================================="

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install and configure AWS CLI first."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Step 1: Backend Infrastructure
echo "📦 Step 1/3: Deploying Backend Infrastructure..."
./backend_bot.sh
if [ $? -ne 0 ]; then
    echo "❌ Backend deployment failed"
    exit 1
fi
echo "✅ Backend infrastructure deployed"
echo ""

# Step 2: Bedrock Knowledge Base
echo "🧠 Step 2/3: Setting up Bedrock Knowledge Base..."
./backend_kb.sh
if [ $? -ne 0 ]; then
    echo "❌ Bedrock setup failed"
    exit 1
fi
echo "✅ Bedrock knowledge base configured"
echo ""

# Step 3: Frontend & API
echo "🌐 Step 3/3: Deploying Frontend & API..."
./cloudfront_setup.sh
if [ $? -ne 0 ]; then
    echo "❌ Frontend deployment failed"
    exit 1
fi
echo "✅ Frontend and API deployed"
echo ""

echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================="
echo "Your AI Quotation Processor is now live!"
echo ""
echo "Check the output above for your application URLs."
echo "The system is ready to process quotation documents."