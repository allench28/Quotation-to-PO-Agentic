# AI Quotation Processor

An AI-powered system that processes quotation documents (PDF/Word) and generates purchase orders using AWS Bedrock.

## Architecture

- **Frontend**: HTML/JS app hosted on S3 + CloudFront
- **API**: API Gateway + Lambda functions
- **AI Processing**: AWS Bedrock (Claude 3 Sonnet)
- **Storage**: DynamoDB for data, S3 for documents
- **Infrastructure**: Complete AWS CLI deployment

## Features

- Upload PDF/Word quotation documents
- AI extraction of key information:
  - Company name and email
  - Quote number and date
  - Line items with quantities and prices
  - Subtotal and total amounts
- Automatic purchase order generation
- Secure cloud storage and processing

## Deployment

### Prerequisites

- AWS CLI configured with appropriate permissions
- Internet connection for AWS API calls

### Complete Deployment

**Windows (us-east-2):**
```cmd
deploy-windows.bat
```

**Linux/Mac (us-east-1):**
```bash
chmod +x *.sh
./deploy-all.sh
```

### What Gets Deployed

- ✅ **Backend**: DynamoDB, S3 buckets, Lambda function, IAM roles
- ✅ **AI**: Bedrock managed prompts with Claude 3 Sonnet
- ✅ **Frontend**: CloudFront distribution, API Gateway, web interface
- ✅ **Security**: CORS, IAM permissions, HTTPS

### Access URLs

After deployment completes, you'll get:
- **CloudFront URL** (HTTPS) - Main application access
- **API Gateway URL** - Backend API endpoint
- **S3 Website URL** - Direct S3 access (HTTP)

## Usage

1. Open the web application
2. Upload a quotation document (PDF or Word)
3. Wait for AI processing (30-60 seconds)
4. Review extracted information and generated purchase order
5. Data is automatically stored in DynamoDB for future reference

## Cost Optimization

- Lambda functions use pay-per-request pricing
- DynamoDB uses on-demand billing
- S3 storage costs are minimal for documents
- Bedrock charges per API call (~$0.003 per 1K tokens)

## Security Features

- CORS enabled for secure frontend communication
- IAM roles with least-privilege access
- CloudFront for secure content delivery
- No hardcoded credentials

## Monitoring

- CloudWatch logs for Lambda functions
- API Gateway request/response logging
- DynamoDB metrics available in CloudWatch

## Customization

### Adding New Document Types
Modify `extract_text()` function in `backend/document_processor.py`

### Changing AI Model
Update the managed prompt in AWS Bedrock console or modify `enhanced-prompt.json`

### UI Modifications
Edit `frontend/index.html` for styling and functionality changes