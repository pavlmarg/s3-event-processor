# Calculate the time window for the last 10 minutes in UTC (ISO 8601 format)
Write-Host "Calculating time window..." -ForegroundColor Cyan
$StartTime = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString("yyyy-MM-ddTHH:mm:ssZ")
$EndTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Check Lambda invocation metrics
Write-Host "Fetching Lambda Invocation Metrics from CloudWatch..." -ForegroundColor Cyan
aws cloudwatch get-metric-statistics `
    --namespace AWS/Lambda `
    --metric-name Invocations `
    --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME `
    --start-time $StartTime `
    --end-time $EndTime `
    --period 300 `
    --statistics Sum