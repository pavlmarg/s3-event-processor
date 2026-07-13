# Create test data file locally
Write-Host "Creating test CSV file..." -ForegroundColor Cyan
$CsvContent = @"
name,age,city
John,30,New York
Jane,25,Los Angeles
"@
$CsvContent | Out-File -FilePath "test-data.csv" -Encoding ascii

# Upload to S3 to trigger processing
Write-Host "Uploading test file to S3 bucket..." -ForegroundColor Cyan
aws s3 cp .\test-data.csv "s3://$BUCKET_NAME/data/test-data.csv"

Write-Host "Test file uploaded! The architecture has been triggered." -ForegroundColor Green