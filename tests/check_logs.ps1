# Check Lambda log groups
Write-Host "Fetching Log Groups..." -ForegroundColor Cyan
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$LAMBDA_FUNCTION_NAME"

# Wait a few seconds to ensure logs have time to be written to CloudWatch
Write-Host "Waiting 15 seconds for logs to populate..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Calculate the timestamp for 5 minutes ago in milliseconds
$StartTime = [int64](([datetime]::UtcNow.AddMinutes(-5) - [datetime]'1970-01-01T00:00:00Z').TotalMilliseconds)

# Get recent log events and format them as a readable table
Write-Host "Fetching recent log events..." -ForegroundColor Cyan
aws logs filter-log-events --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" --start-time $StartTime --query 'events[*].[timestamp,message]' --output table