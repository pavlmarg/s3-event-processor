import json
import boto3
import urllib.parse
from datetime import datetime
import logging
import os
import csv

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing object: {key} from bucket: {bucket}")
            
            # Get object metadata
            response = s3.head_object(Bucket=bucket, Key=key)
            file_size = response['ContentLength']
            last_modified = response['LastModified']
            
            # Example processing logic based on file type
            if key.endswith('.csv'):
                process_csv_file(bucket, key, file_size)
            elif key.endswith('.json'):
                process_json_file(bucket, key, file_size)
            else:
                logger.info(f"Unsupported file type: {key}")
                continue
            
            # Create processing report
            create_processing_report(bucket, key, file_size, last_modified)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed S3 events')
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        # Send to DLQ for retry logic
        send_to_dlq(event, str(e))
        raise e

def process_csv_file(bucket, key, file_size):
    """Process CSV files"""
    logger.info(f"Processing CSV file: {key} (Size: {file_size} bytes)")
    
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        
        # Read the content, decode it from bytes to strings, and split it by line
        csv_content = response['Body'].read().decode('utf-8').splitlines()
        
        # Parse the CSV data
        csv_reader = csv.reader(csv_content)
        headers = next(csv_reader, None)
        
        # Count all rows
        row_count = sum(1 for row in csv_reader)
        
        logger.info(f"CSV Processing Complete! Headers: {headers} | Total Data Rows: {row_count}")
        
    except Exception as e:
        logger.error(f"Failed to parse CSV file {key}: {str(e)}")
        raise e
    
def process_json_file(bucket, key, file_size):
    """Process JSON files"""
    logger.info(f"Processing JSON file: {key} (Size: {file_size} bytes)")
    
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        
        # Read, decode, and parse the JSON content into a Python object
        json_content = json.loads(response['Body'].read().decode('utf-8'))
        
        # Business logic: Analyze the structure of the JSON data
        if isinstance(json_content, list):
            logger.info(f"JSON Processing Complete! Found a list containing {len(json_content)} items.")
        elif isinstance(json_content, dict):
            keys = list(json_content.keys())
            logger.info(f"JSON Processing Complete! Found a dictionary with top-level keys: {keys}")
        else:
            logger.info("JSON Processing Complete! Data is a standalone value.")
            
    except Exception as e:
        logger.error(f"Failed to parse JSON file {key}: {str(e)}")
        raise e

def create_processing_report(bucket, key, file_size, last_modified):
    """Create a processing report and store it in S3"""
    report_key = f"reports/{key.replace('/', '_')}-report-{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
    
    report = {
        'file_processed': key,
        'file_size': file_size,
        'last_modified': last_modified.isoformat(),
        'processing_time': datetime.now().isoformat(),
        'status': 'completed',
        'processor_version': '1.0'
    }
    
    s3.put_object(
        Bucket=bucket,
        Key=report_key,
        Body=json.dumps(report, indent=2),
        ContentType='application/json'
    )
    logger.info(f"Processing report created: {report_key}")

def send_to_dlq(event, error_message):
    """Send failed event to DLQ for retry"""
    dlq_url = os.environ.get('DLQ_URL')
    
    if dlq_url:
        message = {
            'original_event': event,
            'error_message': error_message,
            'timestamp': datetime.now().isoformat(),
            'retry_count': 1
        }
        try:
            sqs.send_message(
                QueueUrl=dlq_url,
                MessageBody=json.dumps(message)
            )
            logger.info("Failed event sent to DLQ")
        except Exception as dlq_error:
            logger.error(f"Failed to send message to DLQ: {str(dlq_error)}")