// index.js
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "crypto";

const client = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(client);

// Get the table name from an environment variable
const tableName = process.env.TABLE_NAME;

export const handler = async (event) => {
  // The request body will be a JSON string, parse it
  const body = JSON.parse(event.body);

  const params = {
    TableName: tableName,
    Item: {
      id: randomUUID(), // Generate a unique ID for the to-do item
      task: body.task,
      completed: false,
      createdAt: new Date().toISOString(),
    },
  };

  try {
    await ddbDocClient.send(new PutCommand(params));
    return {
      statusCode: 201, // 201 Created
      body: JSON.stringify({ message: "To-do item created successfully", item: params.Item }),
    };
  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      body: JSON.stringify({ message: "Could not create to-do item" }),
    };
  }
};