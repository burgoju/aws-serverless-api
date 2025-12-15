const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Test DynamoDB connection
        await dynamodb.scan({
            TableName: 'users-table',
            Limit: 1
        }).promise();
        
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                status: 'healthy',
                service: 'serverless-api',
                timestamp: new Date().toISOString(),
                region: process.env.AWS_REGION || 'us-east-1',
                dynamodb: 'connected'
            })
        };
        
    } catch (error) {
        console.error('Health check failed:', error);
        
        return {
            statusCode: 503,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                status: 'unhealthy',
                service: 'serverless-api',
                timestamp: new Date().toISOString(),
                dynamodb: 'disconnected',
                error: error.message
            })
        };
    }
};
