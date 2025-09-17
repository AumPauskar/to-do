# main.tf

# --- Provider & AWS Configuration ---
provider "aws" {
  region = "us-east-1" # You can change this to your preferred region
}

# --- DynamoDB Table ---
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- IAM Role & Policy for Lambda ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_dynamodb_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attaches the standard AWS-managed policy for Lambda logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attaches a custom policy to allow access to our DynamoDB table
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "lambda_dynamodb_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Scan"],
      Effect   = "Allow",
      Resource = aws_dynamodb_table.todo_table.arn
    }]
  })
}

# --- Lambda Function ---
resource "aws_lambda_function" "todo_lambda" {
  filename      = "lambda_function.zip"
  function_name = "todo-api-lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x" # Using a modern Node.js runtime

  # Pass the table name to the function as an environment variable
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

# --- API Gateway ---
resource "aws_api_gateway_rest_api" "api" {
  name        = "TodoAPI"
  description = "API for the To-Do List application"
}

resource "aws_api_gateway_resource" "todos_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "todos" # This creates the /todos path
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.todos_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.todos_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todo_lambda.invoke_arn
}

# --- API Gateway Deployment ---
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # This ensures the API is re-deployed whenever the configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.todos_resource.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "dev"
}

# --- Lambda Permission ---
# This grants API Gateway permission to invoke our Lambda function
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.post_method.http_method}${aws_api_gateway_resource.todos_resource.path}"
}

# --- Outputs ---
output "api_invoke_url" {
  description = "The base URL for the API stage"
  value       = "${aws_api_gateway_stage.api_stage.invoke_url}/todos"
}