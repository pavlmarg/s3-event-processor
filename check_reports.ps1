# List objects in the reports folder
Write-Host "Listing files in the reports folder..." -ForegroundColor Cyan
aws s3 ls "s3://$BUCKET_NAME/reports/"

# Fetch the exact key of the first report using an AWS CLI query
Write-Host "`nDownloading the latest report..." -ForegroundColor Cyan
$REPORT_KEY = aws s3api list-objects-v2 --bucket $BUCKET_NAME --prefix "reports/" `
    --query 'Contents[0].Key' --output text

# Download and view the report if it exists
if ($REPORT_KEY -and $REPORT_KEY -ne "None" -and $REPORT_KEY -ne "null") {
    # Download the file to your current VS Code directory
    aws s3 cp "s3://$BUCKET_NAME/$REPORT_KEY" .\report.json
    
    Write-Host "`n Processing report downloaded! Here are the contents:" -ForegroundColor Green
    
    # Print the JSON contents to the terminal (Replaces Linux 'cat' and 'jq')
    Get-Content .\report.json
} else {
    Write-Host "No reports found. The Lambda function might still be processing or encountered an error." -ForegroundColor Yellow
}