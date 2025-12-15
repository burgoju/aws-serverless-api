const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const { v4: uuidv4 } = require('uuid');

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        const body = JSON.parse(event.body || '{}');
        const { name, email, age } = body;
        
        // Validation
        if (!name || !email) {
            return {
                statusCode: 400,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                body: JSON.stringify({
                    error: 'Name and email are required'
                })
            };
        }
        
        const userId = uuidv4();
        const timestamp = new Date().toISOString();
        
        const userItem = {
            userId,
            name,
            email,
            age: age || null,
            createdAt: timestamp,
            updatedAt: timestamp
        };
        
        // Store in DynamoDB
        await dynamodb.put({
            TableName: 'users-table',
            Item: userItem
        }).promise();
        
        return {
            statusCode: 201,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                message: 'User created successfully',
                user: userItem
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
