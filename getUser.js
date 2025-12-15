const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Get query parameters
        const queryParams = event.queryStringParameters || {};
        const limit = parseInt(queryParams.limit) || 10;
        const lastEvaluatedKey = queryParams.lastKey ? 
            JSON.parse(decodeURIComponent(queryParams.lastKey)) : null;
        
        // Scan DynamoDB table
        const scanParams = {
            TableName: 'users-table',
            Limit: limit
        };
        
        if (lastEvaluatedKey) {
            scanParams.ExclusiveStartKey = lastEvaluatedKey;
        }
        
        const result = await dynamodb.scan(scanParams).promise();
        
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                users: result.Items,
                count: result.Items.length,
                totalCount: result.ScannedCount,
                lastEvaluatedKey: result.LastEvaluatedKey,
                hasMore: !!result.LastEvaluatedKey
            })
        };
        
    } catch (error) {
        console.error('Error:', error);
        
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                error: 'Internal server error',
                details: error.message
            })
        };
    }
};
