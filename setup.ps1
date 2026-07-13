# Set environment variables
$AWS_REGION = aws configure get region
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

# Generate unique identifiers for resources
$RANDOM_SUFFIX = aws secretsmanager get-random-password --exclude-punctuation --exclude-uppercase --password-length 6 --require-each-included-type --output text --query RandomPassword

$BUCKET_NAME = "data-processing-$RANDOM_SUFFIX"
$LAMBDA_FUNCTION_NAME = "data-processor-$RANDOM_SUFFIX"
$ERROR_HANDLER_NAME = "error-handler-$RANDOM_SUFFIX"
$DLQ_NAME = "data-processing-dlq-$RANDOM_SUFFIX"
$SNS_TOPIC_NAME = "data-processing-alerts-$RANDOM_SUFFIX"
$LAMBDA_ROLE_NAME = "data-processing-lambda-role-$RANDOM_SUFFIX"

Write-Host "Environment variables configured" -ForegroundColor Green
Write-Host "Bucket: $BUCKET_NAME"
Write-Host "Lambda Function: $LAMBDA_FUNCTION_NAME"

# Create the S3 bucket (region-specific creation)
aws s3api create-bucket --bucket $BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION

# Enable versioning for data management
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

Write-Host "S3 bucket created: $BUCKET_NAME" -ForegroundColor Green

# Create SNS topic for alerts
$SNS_TOPIC_ARN = aws sns create-topic --name $SNS_TOPIC_NAME --query TopicArn --output text

# Subscribe email to the topic 
aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint paulosmargarites553@gmail.com

Write-Host "SNS topic created: $SNS_TOPIC_ARN" -ForegroundColor Green
Write-Host "ACTION REQUIRED: Please check your email and confirm the subscription!" -ForegroundColor Yellow

# Create dead letter queue for failed processing
$DLQ_URL = aws sqs create-queue --queue-name $DLQ_NAME --attributes VisibilityTimeout=300 --query QueueUrl --output text

# Get DLQ ARN
$DLQ_ARN = aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names QueueArn --query Attributes.QueueArn --output text

Write-Host "Dead Letter Queue created: $DLQ_ARN" -ForegroundColor Green

# Create the Trust Policy (Tells AWS that Lambda is allowed to use this role)
$TrustPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
"@
$TrustPolicy | Out-File -FilePath "trust-policy.json" -Encoding ascii

# Create the actual IAM Role using the Trust Policy
aws iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document file://trust-policy.json | Out-Null

# Create your Custom Permissions Policy for S3, SQS, and SNS
$ExecutionPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": [
                "$DLQ_ARN"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": [
                "$SNS_TOPIC_ARN"
            ]
        }
    ]
}
"@
$ExecutionPolicy | Out-File -FilePath "lambda-execution-policy.json" -Encoding ascii

# Attach custom Permissions Policy to the Role
aws iam put-role-policy --role-name $LAMBDA_ROLE_NAME --policy-name DataProcessingPolicy --policy-document file://lambda-execution-policy.json

# Attach the basic AWS managed policy so Lambda can write error logs to CloudWatch
aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

Write-Host "IAM Role and security policies successfully created and attached" -ForegroundColor Green

# Zip up the Python application code
Write-Host "Zipping deployment package..." -ForegroundColor Cyan
Compress-Archive -Path .\lambda_function.py -DestinationPath .\data_processor.zip -Force

# Wait for IAM role to propagate
Write-Host "Waiting 15 seconds for IAM role to propagate through AWS..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Create the Lambda function
$LAMBDA_ARN = aws lambda create-function `
    --function-name $LAMBDA_FUNCTION_NAME `
    --runtime python3.12 `
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" `
    --handler lambda_function.lambda_handler `
    --zip-file fileb://data_processor.zip `
    --timeout 300 `
    --memory-size 512 `
    --environment Variables="{DLQ_URL=$DLQ_URL}" `
    --dead-letter-config TargetArn=$DLQ_ARN `
    --query FunctionArn --output text

Write-Host "Data processing Lambda function created: $LAMBDA_ARN" -ForegroundColor Green

# Zip up the Python error handler code
Write-Host "Zipping error handler package..." -ForegroundColor Cyan
Compress-Archive -Path .\error_handler.py -DestinationPath .\error_handler.zip -Force

# Create the Error Handler Lambda function
$ERROR_HANDLER_ARN = aws lambda create-function `
    --function-name $ERROR_HANDLER_NAME `
    --runtime python3.12 `
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" `
    --handler error_handler.lambda_handler `
    --zip-file fileb://error_handler.zip `
    --timeout 60 `
    --memory-size 256 `
    --environment Variables="{SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" `
    --query FunctionArn --output text

Write-Host "Error handler Lambda function created: $ERROR_HANDLER_ARN" -ForegroundColor Green

# Create event source mapping for DLQ to error handler
Write-Host "Connecting SQS Dead Letter Queue to Error Handler Lambda..." -ForegroundColor Cyan
aws lambda create-event-source-mapping `
    --function-name $ERROR_HANDLER_NAME `
    --event-source-arn $DLQ_ARN `
    --batch-size 10 `
    --maximum-batching-window-in-seconds 5 | Out-Null

Write-Host "SQS event source mapping created for error handler" -ForegroundColor Green


# Add permission for S3 to invoke the main Lambda
Write-Host "Granting S3 permission to invoke the Data Processor Lambda..." -ForegroundColor Cyan
aws lambda add-permission `
    --function-name $LAMBDA_FUNCTION_NAME `
    --principal s3.amazonaws.com `
    --action "lambda:InvokeFunction" `
    --statement-id s3-trigger-permission `
    --source-arn "arn:aws:s3:::$BUCKET_NAME" | Out-Null

Write-Host "S3 permission granted to invoke Lambda" -ForegroundColor Green

# Create notification configuration with a folder filter
Write-Host "Configuring advanced S3 Event Trigger..." -ForegroundColor Cyan

$NotificationConfig = @"
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "data-processing-notification",
            "LambdaFunctionArn": "$LAMBDA_ARN",
            "Events": [
                "s3:ObjectCreated:*"
            ],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "data/"
                        }
                    ]
                }
            }
        }
    ]
}
"@
$NotificationConfig | Out-File -FilePath "notification-config.json" -Encoding ascii

# Apply notification configuration
aws s3api put-bucket-notification-configuration `
    --bucket $BUCKET_NAME `
    --notification-configuration file://notification-config.json

Write-Host "S3 event notifications configured! Architecture is fully wired." -ForegroundColor Green

# Create CloudWatch alarms for system monitoring
Write-Host "Configuring CloudWatch Monitoring Alarms..." -ForegroundColor Cyan

# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm `
    --alarm-name "${LAMBDA_FUNCTION_NAME}-errors" `
    --alarm-description "Monitor Lambda function errors" `
    --metric-name Errors `
    --namespace AWS/Lambda `
    --statistic Sum `
    --period 300 `
    --threshold 1 `
    --comparison-operator GreaterThanOrEqualToThreshold `
    --evaluation-periods 1 `
    --alarm-actions $SNS_TOPIC_ARN `
    --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME

# Create alarm for DLQ message count
aws cloudwatch put-metric-alarm `
    --alarm-name "${DLQ_NAME}-messages" `
    --alarm-description "Monitor DLQ message count" `
    --metric-name ApproximateNumberOfVisibleMessages `
    --namespace AWS/SQS `
    --statistic Average `
    --period 300 `
    --threshold 5 `
    --comparison-operator GreaterThanThreshold `
    --evaluation-periods 1 `
    --alarm-actions $SNS_TOPIC_ARN `
    --dimensions Name=QueueName,Value=$DLQ_NAME

# Create alarm for Lambda duration (performance monitoring)
aws cloudwatch put-metric-alarm `
    --alarm-name "${LAMBDA_FUNCTION_NAME}-duration" `
    --alarm-description "Monitor Lambda function duration" `
    --metric-name Duration `
    --namespace AWS/Lambda `
    --statistic Average `
    --period 300 `
    --threshold 240000 `
    --comparison-operator GreaterThanThreshold `
    --evaluation-periods 2 `
    --alarm-actions $SNS_TOPIC_ARN `
    --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME

Write-Host "CloudWatch alarms created for monitoring! The system is fully complete." -ForegroundColor Green