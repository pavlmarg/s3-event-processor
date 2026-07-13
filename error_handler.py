import json
import boto3
from datetime import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Process SQS messages from DLQ
        for record in event['Records']:
            message_body = json.loads(record['body'])
            
            # Extract error details
            error_message = message_body.get('error_message', 'Unknown error')
            timestamp = message_body.get('timestamp', datetime.now().isoformat())
            original_event = message_body.get('original_event', {})
            retry_count = message_body.get('retry_count', 1)
            
            # Extract S3 object details if available
            s3_details = ""
            if original_event and 'Records' in original_event:
                try:
                    s3_record = original_event['Records'][0]['s3']
                    bucket_name = s3_record['bucket']['name']
                    object_key = s3_record['object']['key']
                    s3_details = f"Bucket: {bucket_name}, Object: {object_key}"
                except (KeyError, IndexError):
                    s3_details = "S3 details not available"
            
            # Send alert via SNS
            alert_message = f"""
Data Processing Error Alert

Error: {error_message}
Timestamp: {timestamp}
Retry Attempt: {retry_count}
{s3_details}

Please investigate the failed processing job.
Check CloudWatch Logs for detailed error information.
            """
            
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            
            if sns_topic_arn:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Message=alert_message.strip(),
                    Subject='Data Processing Error Alert'
                )
            
            logger.info(f"Error alert sent for: {error_message}")
            
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Error handling completed')
    }