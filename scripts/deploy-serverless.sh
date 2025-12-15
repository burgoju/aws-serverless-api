#!/bin/bash
# Serverless API Deployment Script

echo "🚀 Deploying Serverless API with Lambda & API Gateway..."
echo "=========================================================="

# Configuration
REGION="us-east-1"
STACK_NAME="serverless-users-api"
BUCKET_NAME="serverless-frontend-$(date +%s)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}📋 Configuration:${NC}"
echo "  Region: $REGION"
echo "  Stack Name: $STACK_NAME"
echo "  Frontend Bucket: $BUCKET_NAME"

# 1. Create S3 Bucket for Frontend
echo -e "\n${YELLOW}1. Creating S3 Bucket for Frontend...${NC}"
aws s3 mb s3://$BUCKET_NAME --region $REGION

aws s3 website s3://$BUCKET_NAME \
    --index-document index.html \
    --error-document error.html

# Create bucket policy for public access
cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file://bucket-policy.json

echo -e "${GREEN}✅ S3 Bucket created: $BUCKET_NAME${NC}"

# 2. Create CloudFormation Stack
echo -e "\n${YELLOW}2. Creating CloudFormation Stack...${NC}"

# CloudFormation template
cat > cloudformation-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Day 6 - Serverless Users API with Lambda, API Gateway, and DynamoDB'

Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues:
      - dev
      - staging
      - prod

Resources:
  # DynamoDB Table
  UsersTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: !Sub users-table-${Environment}
      BillingMode: PAY_PER_REQUEST
      AttributeDefinitions:
        - AttributeName: userId
          AttributeType: S
      KeySchema:
        - AttributeName: userId
          KeyType: HASH
      SSESpecification:
        SSEEnabled: true

  # IAM Role for Lambda
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: LambdaDynamoDBPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - dynamodb:PutItem
                  - dynamodb:GetItem
                  - dynamodb:UpdateItem
                  - dynamodb:DeleteItem
                  - dynamodb:Scan
                Resource: !GetAtt UsersTable.Arn
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                Resource: arn:aws:logs:*:*:*

  # Lambda Functions
  CreateUserFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub create-user-${Environment}
      Runtime: nodejs18.x
      Handler: index.handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          const AWS = require('aws-sdk');
          const dynamodb = new AWS.DynamoDB.DocumentClient();
          const { v4: uuidv4 } = require('uuid');

          exports.handler = async (event) => {
              try {
                  const body = JSON.parse(event.body);
                  const { name, email, age } = body;
                  
                  if (!name || !email) {
                      return {
                          statusCode: 400,
                          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
                          body: JSON.stringify({ error: 'Name and email are required' })
                      };
                  }
                  
                  const userId = uuidv4();
                  const timestamp = new Date().toISOString();
                  
                  const userItem = { userId, name, email, age: age || null, createdAt: timestamp, updatedAt: timestamp };
                  
                  await dynamodb.put({ TableName: 'users-table-dev', Item: userItem }).promise();
                  
                  return {
                      statusCode: 201,
                      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
                      body: JSON.stringify({ message: 'User created', user: userItem })
                  };
              } catch (error) {
                  return {
                      statusCode: 500,
                      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
                      body: JSON.stringify({ error: error.message })
                  };
              }
          };
      Environment:
        Variables:
          TABLE_NAME: !Ref UsersTable
      Timeout: 10

  GetUsersFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub get-users-${Environment}
      Runtime: nodejs18.x
      Handler: index.handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          const AWS = require('aws-sdk');
          const dynamodb = new AWS.DynamoDB.DocumentClient();

          exports.handler = async (event) => {
              try {
                  const result = await dynamodb.scan({ TableName: 'users-table-dev' }).promise();
                  
                  return {
                      statusCode: 200,
                      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
                      body: JSON.stringify({ users: result.Items, count: result.Items.length })
                  };
              } catch (error) {
                  return {
                      statusCode: 500,
                      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
                      body: JSON.stringify({ error: error.message })
                  };
              }
          };
      Environment:
        Variables:
          TABLE_NAME: !Ref UsersTable
      Timeout: 10

  # API Gateway
  ApiGateway:
    Type: AWS::ApiGateway::RestApi
    Properties:
      Name: !Sub serverless-users-api-${Environment}
      Description: Serverless Users API

  ApiResourceUsers:
    Type: AWS::ApiGateway::Resource
    Properties:
      ParentId: !GetAtt ApiGateway.RootResourceId
      PathPart: users
      RestApiId: !Ref ApiGateway

  ApiMethodUsersGET:
    Type: AWS::ApiGateway::Method
    Properties:
      RestApiId: !Ref ApiGateway
      ResourceId: !Ref ApiResourceUsers
      HttpMethod: GET
      AuthorizationType: NONE
      Integration:
        Type: AWS_PROXY
        IntegrationHttpMethod: POST
        Uri: !Sub arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${GetUsersFunction.Arn}/invocations

  ApiMethodUsersPOST:
    Type: AWS::ApiGateway::Method
    Properties:
      RestApiId: !Ref ApiGateway
      ResourceId: !Ref ApiResourceUsers
      HttpMethod: POST
      AuthorizationType: NONE
      Integration:
        Type: AWS_PROXY
        IntegrationHttpMethod: POST
        Uri: !Sub arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${CreateUserFunction.Arn}/invocations

  # Lambda Permissions
  ApiGatewayInvokeCreateUser:
    Type: AWS::Lambda::Permission
    Properties:
      Action: lambda:InvokeFunction
      FunctionName: !Ref CreateUserFunction
      Principal: apigateway.amazonaws.com
      SourceArn: !Sub arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${ApiGateway}/*/POST/users

  ApiGatewayInvokeGetUsers:
    Type: AWS::Lambda::Permission
    Properties:
      Action: lambda:InvokeFunction
      FunctionName: !Ref GetUsersFunction
      Principal: apigateway.amazonaws.com
      SourceArn: !Sub arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${ApiGateway}/*/GET/users

  # API Gateway Deployment
  ApiDeployment:
    Type: AWS::ApiGateway::Deployment
    DependsOn:
      - ApiMethodUsersGET
      - ApiMethodUsersPOST
    Properties:
      RestApiId: !Ref ApiGateway
      StageName: prod

Outputs:
  ApiGatewayUrl:
    Description: API Gateway Endpoint URL
    Value: !Sub https://${ApiGateway}.execute-api.${AWS::Region}.amazonaws.com/prod
  S3WebsiteUrl:
    Description: S3 Website URL
    Value: !Sub http://${BUCKET_NAME}.s3-website.${AWS::Region}.amazonaws.com
  UsersTableName:
    Description: DynamoDB Table Name
    Value: !Ref UsersTable
EOF

# Deploy CloudFormation stack
aws cloudformation deploy \
    --template-file cloudformation-template.yaml \
    --stack-name $STACK_NAME \
    --parameter-overrides Environment=dev \
    --capabilities CAPABILITY_IAM \
    --region $REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ CloudFormation stack deployed successfully${NC}"
    
    # Get outputs
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" \
        --output text \
        --region $REGION)
    
    echo -e "\n${YELLOW}📊 Deployment Outputs:${NC}"
    echo "  API Gateway URL: $API_URL"
    echo "  S3 Website URL: http://$BUCKET_NAME.s3-website.$REGION.amazonaws.com"
else
    echo -e "${RED}❌ CloudFormation deployment failed${NC}"
    exit 1
fi

# 3. Upload Frontend Files
echo -e "\n${YELLOW}3. Uploading Frontend Files...${NC}"

# Create index.html with API URL
cat > index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Serverless Users API</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .api-url { background: #f0f0f0; padding: 15px; border-radius: 5px; font-family: monospace; }
        .endpoint { margin: 20px 0; padding: 15px; background: #f9f9f9; border-left: 4px solid #4CAF50; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Serverless Users API - Day 6</h1>
        <p>API Gateway URL:</p>
        <div class="api-url">$API_URL</div>
        
        <h2>Available Endpoints:</h2>
        <div class="endpoint">
            <strong>GET</strong> $API_URL/health<br>
            <em>Health check endpoint</em>
        </div>
        <div class="endpoint">
            <strong>GET</strong> $API_URL/users<br>
            <em>Get all users</em>
        </div>
        <div class="endpoint">
            <strong>POST</strong> $API_URL/users<br>
            <em>Create new user</em>
        </div>
        
        <h2>Test Commands:</h2>
        <pre>
# Health check
curl $API_URL/health

# Get users
curl $API_URL/users

# Create user
curl -X POST $API_URL/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'
        </pre>
    </div>
</body>
</html>
EOF

# Upload to S3
aws s3 cp index.html s3://$BUCKET_NAME/ --acl public-read
aws s3 cp frontend/ s3://$BUCKET_NAME/ --recursive --acl public-read

echo -e "${GREEN}✅ Frontend files uploaded${NC}"

# 4. Create Test Script
echo -e "\n${YELLOW}4. Creating Test Script...${NC}"

cat > test-api.sh << EOF
#!/bin/bash
echo "Testing Serverless API..."
echo "=========================="

API_URL="$API_URL"

# Test health endpoint
echo "1. Testing health endpoint:"
curl -s \$API_URL/health | jq '.'

# Test create user
echo -e "\n2. Creating test user:"
curl -s -X POST \$API_URL/users \\
  -H "Content-Type: application/json" \\
  -d '{"name":"Test User","email":"test@example.com","age":25}' | jq '.'

# Test get users
echo -e "\n3. Getting all users:"
curl -s \$API_URL/users | jq '.'

echo -e "\n✅ API Tests Complete!"
EOF

chmod +x test-api.sh

echo -e "${GREEN}✅ Test script created: ./test-api.sh${NC}"

# 5. Summary
echo -e "\n${YELLOW}🎉 Deployment Complete!${NC}"
echo "=================================="
echo -e "${GREEN}Frontend URL:${NC} http://$BUCKET_NAME.s3-website.$REGION.amazonaws.com"
echo -e "${GREEN}API Gateway URL:${NC} $API_URL"
echo -e "${GREEN}DynamoDB Table:${NC} users-table-dev"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update the frontend index.html with your API URL"
echo "2. Test the API: ./test-api.sh"
echo "3. Monitor logs in CloudWatch"
echo "4. Check costs in AWS Cost Explorer"
echo ""
echo -e "${YELLOW}Cleanup Command:${NC}"
echo "aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION"
echo "aws s3 rb s3://$BUCKET_NAME --force --region $REGION"
