# Create a corrupted file disguised as a JSON to trigger a parsing exception
Write-Host "Creating a corrupted JSON test file..." -ForegroundColor Cyan
"This is strictly invalid text, not a JSON object!" | Out-File -FilePath "invalid-test.json" -Encoding ascii

# Upload to S3 to trigger the failure
Write-Host "Uploading corrupted file to S3..." -ForegroundColor Cyan
aws s3 cp .\invalid-test.json "s3://$BUCKET_NAME/data/invalid-test.json"

# Wait for Lambda to crash, send to SQS, and trigger the Error Handler
Write-Host "Waiting 20 seconds for the system to process the crash..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

# Check DLQ for messages
Write-Host "Checking Dead Letter Queue (DLQ) for messages..." -ForegroundColor Cyan
aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible