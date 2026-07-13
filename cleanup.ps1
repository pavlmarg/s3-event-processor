# =====================================================================
# cleanup.ps1 - Discovers and deletes ALL resources belonging to this
# project by naming pattern (data-processor-*, error-handler-*, etc.),
# regardless of how many setup.ps1 runs/suffixes exist. Safe to re-run;
# =====================================================================

Write-Host "=== DISCOVERING ALL data-processing RESOURCES ===" -ForegroundColor Cyan

# Lambda functions (+ their event source mappings)
Write-Host "`n--- Lambda Functions ---" -ForegroundColor Yellow
$functions = aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'data-processor-') || starts_with(FunctionName, 'error-handler-')].FunctionName" --output text
foreach ($fn in ($functions -split "\s+")) {
    if ($fn) {
        Write-Host "Deleting function: $fn"
        $mappings = aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[].UUID" --output text
        foreach ($uuid in ($mappings -split "\s+")) {
            if ($uuid) { aws lambda delete-event-source-mapping --uuid $uuid | Out-Null }
        }
        aws lambda delete-function --function-name $fn
    }
}

# CloudWatch Alarms 
Write-Host "`n--- CloudWatch Alarms ---" -ForegroundColor Yellow
$alarms = aws cloudwatch describe-alarms --query "MetricAlarms[?starts_with(AlarmName, 'data-processor-') || starts_with(AlarmName, 'data-processing-dlq-')].AlarmName" --output text
if ($alarms) {
    aws cloudwatch delete-alarms --alarm-names ($alarms -split "\s+")
}

# CloudWatch Log Groups 
Write-Host "`n--- CloudWatch Log Groups ---" -ForegroundColor Yellow
$logGroups = aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'data-processor-') || contains(logGroupName, 'error-handler-')].logGroupName" --output text
foreach ($lg in ($logGroups -split "\s+")) {
    if ($lg) {
        Write-Host "Deleting log group: $lg"
        aws logs delete-log-group --log-group-name $lg
    }
}

#  SQS Queues
Write-Host "`n--- SQS Queues ---" -ForegroundColor Yellow
$queueUrls = aws sqs list-queues --queue-name-prefix "data-processing-dlq-" --query "QueueUrls" --output text
foreach ($url in ($queueUrls -split "\s+")) {
    if ($url -and $url -ne "None") {
        Write-Host "Deleting queue: $url"
        aws sqs delete-queue --queue-url $url
    }
}

# SNS Topics 
Write-Host "`n--- SNS Topics ---" -ForegroundColor Yellow
$topics = aws sns list-topics --query "Topics[?contains(TopicArn, 'data-processing-alerts-')].TopicArn" --output text
foreach ($arn in ($topics -split "\s+")) {
    if ($arn) {
        Write-Host "Deleting topic: $arn"
        aws sns delete-topic --topic-arn $arn
    }
}

# IAM Roles 
Write-Host "`nIAM Roles" -ForegroundColor Yellow
$roles = aws iam list-roles --query "Roles[?starts_with(RoleName, 'data-processing-lambda-role-')].RoleName" --output text
foreach ($role in ($roles -split "\s+")) {
    if ($role) {
        Write-Host "Cleaning up role: $role"
        $inlinePolicies = aws iam list-role-policies --role-name $role --query "PolicyNames" --output text
        foreach ($policy in ($inlinePolicies -split "\s+")) {
            if ($policy) { aws iam delete-role-policy --role-name $role --policy-name $policy }
        }
        $attachedPolicies = aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text
        foreach ($policyArn in ($attachedPolicies -split "\s+")) {
            if ($policyArn) { aws iam detach-role-policy --role-name $role --policy-arn $policyArn }
        }
        aws iam delete-role --role-name $role
    }
}

# S3 Buckets
Write-Host "`n--- S3 Buckets ---" -ForegroundColor Yellow
$buckets = aws s3api list-buckets --query "Buckets[?starts_with(Name, 'data-processing-')].Name" --output text
foreach ($bucket in ($buckets -split "\s+")) {
    if ($bucket) {
        Write-Host "Emptying and deleting bucket: $bucket"

        $versionsJson = aws s3api list-object-versions --bucket $bucket --output json --query "{Objects: Versions[].{Key:Key,VersionId:VersionId}}"
        $markersJson  = aws s3api list-object-versions --bucket $bucket --output json --query "{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}"

        $versionsFile = "versions-$bucket.json"
        $markersFile  = "markers-$bucket.json"
        $versionsJson | Out-File -FilePath $versionsFile -Encoding ascii
        $markersJson  | Out-File -FilePath $markersFile  -Encoding ascii

        if ($versionsJson -notmatch '"Objects":\s*null') {
            aws s3api delete-objects --bucket $bucket --delete "file://$versionsFile" | Out-Null
        }
        if ($markersJson -notmatch '"Objects":\s*null') {
            aws s3api delete-objects --bucket $bucket --delete "file://$markersFile" | Out-Null
        }

        Remove-Item $versionsFile, $markersFile -ErrorAction SilentlyContinue

        aws s3 rb "s3://$bucket" --force
    }
}

Write-Host "`n=== CLEANUP COMPLETE ===" -ForegroundColor Green
Write-Host "Verify everything is gone with:" -ForegroundColor Cyan
Write-Host '  aws s3api list-buckets --query "Buckets[?starts_with(Name, ''data-processing-'')].Name"'
Write-Host '  aws lambda list-functions --query "Functions[?starts_with(FunctionName, ''data-processor-'') || starts_with(FunctionName, ''error-handler-'')].FunctionName"'
Write-Host '  aws iam list-roles --query "Roles[?starts_with(RoleName, ''data-processing-lambda-role-'')].RoleName"'
Write-Host '  aws sqs list-queues --queue-name-prefix "data-processing-dlq-"'
Write-Host '  aws sns list-topics --query "Topics[?contains(TopicArn, ''data-processing-alerts-'')]"'
Write-Host '  aws cloudwatch describe-alarms --query "MetricAlarms[?starts_with(AlarmName, ''data-processor-'') || starts_with(AlarmName, ''data-processing-dlq-'')].AlarmName"'