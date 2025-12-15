const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        const userId = event.pathParameters.userId;
        const body = JSON.parse(event.body || '{}');
        const { name, email, age } = body;
        
        if (!userId) {
            return {
                statusCode: 400,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                body: JSON.stringify({
                    error: 'User ID is required'
                })
            };
        }
        
        // Check if user exists
        const existingUser = await dynamodb.get({
            TableName: 'users-table',
            Key: { userId }
        }).promise();
        
        if (!existingUser.Item) {
            return {
                statusCode: 404,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                body: JSON.stringify({
                    error: 'User not found'
                })
            };
        }
        
        // Prepare update expression
        const updateParams = {
            TableName: 'users-table',
            Key: { userId },
            UpdateExpression: 'set #name = :name, email = :email, age = :age, updatedAt = :updatedAt',
            ExpressionAttributeNames: {
                '#name': 'name'
            },
            ExpressionAttributeValues: {
                ':name': name || existingUser.Item.name,
                ':email': email || existingUser.Item.email,
                ':age': age !== undefined ? age : existingUser.Item.age,
                ':updatedAt': new Date().toISOString()
            },
            ReturnValues: 'ALL_NEW'
        };
        
        // Update user
        const result = await dynamodb.update(updateParams).promise();
        
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({
                message: 'User updated successfully',
                user: result.Attributes
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
