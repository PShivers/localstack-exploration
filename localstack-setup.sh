#!/bin/bash

# --- Configuration ---
REGION="us-east-1"
SNS_TOPIC_NAME="my-localstack-topic"
SQS_QUEUE_NAME="my-localstack-queue"
LOCALSTACK_ENDPOINT="http://localhost:4566"  # Default LocalStack endpoint

# --- Helper Functions ---

# Function to check if a resource exists
resource_exists() {
  local resource_type="$1"
  local resource_name="$2"
  local aws_cli_command=""

  case "$resource_type" in
    "sns")
      aws_cli_command="aws sns list-topics --endpoint-url $LOCALSTACK_ENDPOINT --region $REGION --query 'Topics[*].TopicArn' --output text | grep '$resource_name'"
      ;;
    "sqs")
      aws_cli_command="aws sqs list-queues --endpoint-url $LOCALSTACK_ENDPOINT --region $REGION --query 'QueueUrls[*]' --output text | grep '$resource_name'"
      ;;
    *)
      echo "Error: Unsupported resource type: $resource_type"
      return 1
      ;;
  esac

  if eval "$aws_cli_command"; then
    return 0 # Resource exists
  else
    return 1 # Resource does not exist
  fi
}

# Function to create an SNS topic
create_sns_topic() {
  if resource_exists "sns" "$SNS_TOPIC_NAME"; then
    echo "SNS topic '$SNS_TOPIC_NAME' already exists."
  else
    echo "Creating SNS topic '$SNS_TOPIC_NAME'..."
    aws sns create-topic --name "$SNS_TOPIC_NAME" --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION"
    if [ $? -eq 0 ]; then
      echo "SNS topic '$SNS_TOPIC_NAME' created successfully."
    else
      echo "Error creating SNS topic '$SNS_TOPIC_NAME'."
    fi
  fi
}

# Function to create an SQS queue
create_sqs_queue() {
  if resource_exists "sqs" "$SQS_QUEUE_NAME"; then
    echo "SQS queue '$SQS_QUEUE_NAME' already exists."
  else
    echo "Creating SQS queue '$SQS_QUEUE_NAME'..."
    aws sqs create-queue --queue-name "$SQS_QUEUE_NAME" --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION"
    if [ $? -eq 0 ]; then
      echo "SQS queue '$SQS_QUEUE_NAME' created successfully."
    else
      echo "Error creating SQS queue '$SQS_QUEUE_NAME'."
    fi
  fi
}

# Function to subscribe the SQS queue to the SNS topic
subscribe_sqs_to_sns() {
  local topic_arn=$(aws sns list-topics --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
  local queue_url=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION" --query "QueueUrl" --output text)

  if [ -n "$topic_arn" ] && [ -n "$queue_url" ]; then
    echo "Subscribing SQS queue '$SQS_QUEUE_NAME' to SNS topic '$SNS_TOPIC_NAME'..."

    # Get the SQS queue ARN
    local queue_arn=$(aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION" --query "Attributes.QueueArn" --output text)

    # Set permissions for SNS to send messages to the SQS queue
    aws sqs set-queue-attributes --queue-url "$queue_url" --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Sid\\\":\\\"AllowSNStoSQS\\\",\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"sns.amazonaws.com\\\"},\\\"Action\\\":\\\"sqs:SendMessage\\\",\\\"Resource\\\":\\\"$queue_arn\\\",\\\"Condition\\\":{\\\"ArnEquals\\\":{\\\"aws:SourceArn\\\":\\\"$topic_arn\\\"}}}]}\"}" --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION"

    # Subscribe the queue to the topic
    aws sns subscribe --topic-arn "$topic_arn" --protocol sqs --endpoint "$queue_arn" --endpoint-url "$LOCALSTACK_ENDPOINT" --region "$REGION"
    if [ $? -eq 0 ]; then
      echo "SQS queue '$SQS_QUEUE_NAME' subscribed to SNS topic '$SNS_TOPIC_NAME' successfully."
    else
      echo "Error subscribing SQS queue '$SQS_QUEUE_NAME' to SNS topic '$SNS_TOPIC_NAME'."
    fi
  else
    echo "Error: Could not find SNS topic ARN or SQS queue URL."
    if [ -z "$topic_arn" ]; then
      echo "  SNS Topic ARN not found."
    fi
    if [ -z "$queue_url" ]; then
      echo "  SQS Queue URL not found."
    fi
  fi
}

# --- Main Script ---

echo "Starting LocalStack SNS and SQS creation..."

# Ensure AWS CLI is installed and configured (for LocalStack)
if ! command -v aws &> /dev/null; then
  echo "Error: AWS CLI is not installed. Please install it (e.g., 'pip install awscli')."
  exit 1
fi

# Create SNS topic
create_sns_topic

# Create SQS queue
create_sqs_queue

# Subscribe SQS queue to SNS topic
subscribe_sqs_to_sns

echo "Finished LocalStack SNS and SQS creation."