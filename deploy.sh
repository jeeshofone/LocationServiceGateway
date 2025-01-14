#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Disable AWS CLI pagination globally
export AWS_PAGER=""

# Purpose: Deploy or remove multi-region geo mapping and API services with latency-based routing
#
# This script manages AWS CloudFormation stacks for geographic mapping services and APIs across
# multiple regions. It supports:
# - Custom domain configuration with Route53 latency-based routing
# - CORS configuration for API security
# - AWS profile selection for different environments
# - Full stack deployment and removal capabilities
#
# Prerequisites:
# - AWS CLI installed and configured with appropriate permissions
# - Route53 hosted zone for domain management
# - Valid domain name for API endpoints
#
# Usage:
#   ./deploy.sh --api-domain <api-domain> --web-domain <web-domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]

# Default values
API_DOMAIN_NAME=""
WEB_DOMAIN_NAME=""
CORS_ORIGIN=""
HostedZoneId=""
S3_BUCKET_NAME=""
aws_profile="default"
DEPLOY_REGIONS="us-east-1 ap-southeast-2"
# Regionals available for deployment of Amazon Location Service include:
# us-east-1, us-east-2, us-west-2, ap-south-1, ap-southeast-1, ap-southeast-2, ap-southeast-5, ap-northeast-1, ca-central-1, eu-central-1, eu-west-1, eu-west-2, eu-south-2, eu-north-1, sa-east-1
# DEPLOY_REGIONS="us-east-1 us-east-2 us-west-2 ap-south-1 ap-southeast-1 ap-southeast-2 ap-southeast-5 ap-northeast-1 ca-central-1 eu-central-1 eu-west-1 eu-west-2 eu-south-2 eu-north-1 sa-east-1"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-domain)
            API_DOMAIN_NAME="$2"
            shift 2
            ;;
        --web-domain)
            WEB_DOMAIN_NAME="$2"
            shift 2
            ;;
        --hosted-zone)
            HostedZoneId="$2"
            shift 2
            ;;
        --cors)
            CORS_ORIGIN="$2"
            shift 2
            ;;
        --profile)
            aws_profile="$2"
            shift 2
            ;;
        --bucket)
            S3_BUCKET_NAME="$2"
            shift 2
            ;;
        --remove)
            REMOVE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Retrieves regional API Gateway domain information and hosted zone details
# 
# Arguments:
#   $1 - AWS region (e.g., us-east-1)
#   $2 - AWS CLI profile name
# Returns:
#   0 - Success, information retrieved
#   1 - Failure, missing information
# Sets global variables:
#   REGIONAL_DOMAIN_NAME - The regional domain name for API Gateway
#   REGIONAL_HOSTED_ZONE_ID - The regional hosted zone ID for API Gateway
fetch_regional_domain_and_hosted_zone() {
    local region=$1
    local profile=$2

    # Fetch the Regional Domain Name using AWS CLI and AWS API Gateway's get-domain-names
    REGIONAL_DOMAIN_NAME=$(aws apigateway get-domain-names --region "$region" --profile "$profile" --query "items[?domainName=='$DOMAIN_NAME'].regionalDomainName" --output text)
    if [ -z "$REGIONAL_DOMAIN_NAME" ]; then
        echo "Regional Domain Name could not be retrieved. Deployment halted."
        exit 1
    else
        echo "Regional Domain Name for $region: $REGIONAL_DOMAIN_NAME"
    fi

    # Dynamically set the HostedZoneId for API Gateway
    REGIONAL_HOSTED_ZONE_ID=$(get_hosted_zone_id "$region")
    if [[ -z "$REGIONAL_HOSTED_ZONE_ID" ]] || [[ -z "$REGIONAL_DOMAIN_NAME" ]]; then
        echo "Missing information for $region; skipping DNS update."
        # Return an error code to signal missing information
        return 1
    fi
    # Return success
    return 0
}

# Maps AWS regions to their corresponding API Gateway hosted zone IDs
# 
# Arguments:
#   $1 - AWS region identifier
# Returns:
#   Hosted zone ID string or "Unknown" if region not recognized
# Reference:
#   https://docs.aws.amazon.com/general/latest/gr/apigateway.html
get_hosted_zone_id() {
    case "$1" in
        "us-east-2") echo "ZOJJZC49E0EPZ" ;;
        "us-east-1") echo "Z1UJRXOUMOOFQ8" ;;
        "us-west-1") echo "Z2MUQ32089INYE" ;;
        "us-west-2") echo "Z2OJLYMUO9EFXC" ;;
        "af-south-1") echo "Z2DHW2332DAMTN" ;;
        "ap-east-1") echo "Z3FD1VL90ND7K5" ;;
        "ap-south-1") echo "Z3VO1THU9YC4UR" ;;
        "ap-south-2") echo "Z0853509Q1135NJ66RUH" ;;
        "ap-northeast-2") echo "Z20JF4UZKIW1U8" ;;
        "ap-northeast-3") echo "Z22ILHG95FLSZ2" ;;
        "ap-southeast-1") echo "ZL327KTPIQFUL" ;;
        "ap-southeast-2") echo "Z2RPCDW04V8134" ;;
        "ap-southeast-3") echo "Z10132843TYUYSLUG4HA3" ;;
        "ap-southeast-4") echo "Z092189423Y7RJK61311D" ;;
        "ap-southeast-5") echo "Z0314042F0KBUTZ3X5HF" ;;
        "ap-northeast-1") echo "Z1YSHQZHG15GKL" ;;
        "ca-central-1") echo "Z19DQILCV0OWEC" ;;
        "ca-west-1") echo "Z04745493436AWVTG1OQY" ;;
        "eu-central-1") echo "Z1U9ULNL0V5AJ3" ;;
        "eu-central-2") echo "Z09222482MK253X48U76H" ;;
        "eu-west-1") echo "ZLY8HYME6SFDD" ;;
        "eu-west-2") echo "ZJ5UAJN8Y3Z2Q" ;;
        "eu-west-3") echo "Z3KY65QIEKYHQQ" ;;
        "eu-north-1") echo "Z3UWIKFBOOGXPP" ;;
        "eu-south-1") echo "Z3BT4WSQ9TDYZV" ;;
        "eu-south-2") echo "Z02499852UI5HEQ5JVWX3" ;;
        "il-central-1") echo "Z07264553HBI44N5X2CKP" ;;
        "sa-east-1") echo "ZCMLWB8V5SYIT" ;;
        "me-south-1") echo "Z20ZBPC0SS8806" ;;
        "me-central-1") echo "Z08780021BKYYY8U0YHTV" ;;
        "us-gov-west-1") echo "Z1K6XKP9SAGWDV" ;;
        "us-gov-east-1") echo "Z3SE9ATJYCRCZJ" ;;
        *) echo "Unknown" ;;
    esac
}

# Deploy the S3/CloudFront website infrastructure
#
# Deploys:
# - S3 bucket for static hosting
# - CloudFront distribution
# - ACM certificate
# - Route53 records
deploy_website() {
    echo "Deploying website infrastructure..."
    
    # Deploy the S3/CloudFront stack in us-east-1 (required for CloudFront)
    aws cloudformation deploy \
        --profile "$aws_profile" \
        --template-file s3-cloudfront.yaml \
        --stack-name website-stack \
        --region us-east-1 \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            DomainName=$WEB_DOMAIN_NAME \
            ApiDomainName=$API_DOMAIN_NAME \
            HostedZoneId=$HostedZoneId

    # Try to get the CloudFront distribution ID from stack outputs first
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --profile "$aws_profile" \
        --stack-name website-stack \
        --region us-east-1 \
        --query 'Stacks[0].Outputs[?OutputKey==`DistributionId`].Value' \
        --output text)

    # If not found in outputs, try to get it from the CloudFront distribution list
    if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
        echo "Distribution ID not found in stack outputs, searching CloudFront distributions..."
        DISTRIBUTION_ID=$(aws cloudfront list-distributions \
            --profile "$aws_profile" \
            --query "DistributionList.Items[?Aliases.Items[?contains(@,'${WEB_DOMAIN_NAME}')]].Id" \
            --output text)
    fi

    if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
        echo "Found distribution ID: $DISTRIBUTION_ID"
        # Create invalidation for all files
        aws cloudfront create-invalidation \
            --profile "$aws_profile" \
            --distribution-id "$DISTRIBUTION_ID" \
            --paths "/*" || echo "Warning: Cache invalidation failed"
    else
        echo "Warning: Could not find CloudFront distribution ID"
    fi

    echo "Website infrastructure deployed"
}

# Remove the S3/CloudFront website infrastructure
remove_website() {
    echo "Removing website infrastructure..."
    
    # Get the S3 bucket name from CloudFormation stack
    S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name website-stack \
        --region us-east-1 \
        --profile "$aws_profile" \
        --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
        --output text)

    # Empty the S3 bucket first
    if [ -n "$S3_BUCKET_NAME" ]; then
        aws s3 rm s3://$S3_BUCKET_NAME --recursive --profile "$aws_profile"
    fi
    
    # Delete the CloudFormation stack
    aws cloudformation delete-stack \
        --profile "$aws_profile" \
        --stack-name website-stack \
        --region us-east-1
    
    aws cloudformation wait stack-delete-complete \
        --profile "$aws_profile" \
        --stack-name website-stack \
        --region us-east-1
        
    echo "Website infrastructure removed"
}

# Deploys geo mapping services and API infrastructure across specified regions using StackSets
#
# Performs the following operations:
# - Creates and deploys CloudFormation StackSet for all regions
# - Sets up custom domain names in API Gateway
# - Configures Route53 latency-based routing
#
# Global variables used:
#   DEPLOY_REGIONS - Space-separated list of target AWS regions
#   DOMAIN_NAME - Custom domain for API endpoints
#   CORS_ORIGIN - Allowed CORS origin
#   HostedZoneId - Route53 hosted zone ID
#   aws_profile - AWS CLI profile name
deployfunction() {

    # Convert space-separated regions to JSON array for AWS CLI
    REGIONS_JSON="["
    for region in $DEPLOY_REGIONS; do
        REGIONS_JSON="$REGIONS_JSON\"$region\","
    done
    REGIONS_JSON="${REGIONS_JSON%,}]"

    # Get AWS account ID using the profile
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$aws_profile" --query 'Account' --output text)
    if [ -z "$ACCOUNT_ID" ]; then
        echo "Failed to get AWS account ID. Please check your AWS credentials."
        exit 1
    fi

    # Step 1: Create or update Location Service API Key StackSet
    if ! aws cloudformation describe-stack-set --stack-set-name LocationServiceStackSet --profile "$aws_profile" 2>/dev/null; then
        # Create new stack set if it doesn't exist
        aws cloudformation create-stack-set \
            --stack-set-name LocationServiceStackSet \
            --template-body file://location-stackset.yaml \
            --capabilities CAPABILITY_NAMED_IAM \
            --permission-model SELF_MANAGED \
            --administration-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AWSCloudFormationStackSetAdministrationRole" \
            --execution-role-name "AWSCloudFormationStackSetExecutionRole" \
            --parameters ParameterKey=CORSOrigin,ParameterValue=$CORS_ORIGIN \
            --profile "$aws_profile"
    else
        # Update existing stack set parameters if they've changed
        aws cloudformation update-stack-set \
            --stack-set-name LocationServiceStackSet \
            --template-body file://location-stackset.yaml \
            --capabilities CAPABILITY_NAMED_IAM \
            --administration-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AWSCloudFormationStackSetAdministrationRole" \
            --execution-role-name "AWSCloudFormationStackSetExecutionRole" \
            --parameters ParameterKey=CORSOrigin,ParameterValue=$CORS_ORIGIN \
            --profile "$aws_profile"
    fi

    # Deploy Location Service stack instances in all regions
    echo "Deploying Location Service API keys..."
    # Try to create stack instances and handle in-progress operations
    LOCATION_OPERATION_ID=$(aws cloudformation create-stack-instances \
        --stack-set-name LocationServiceStackSet \
        --accounts "$ACCOUNT_ID" \
        --regions "$REGIONS_JSON" \
        --operation-preferences MaxConcurrentCount=10,FailureToleranceCount=0 \
        --profile "$aws_profile" \
        --query 'OperationId' \
        --output text 2>&1)

    # Check if there's an operation in progress
    if [[ $LOCATION_OPERATION_ID == *"OperationInProgressException"* ]]; then
        # Extract only the operation ID from the error message using awk to get the last UUID in the message
        IN_PROGRESS_ID=$(echo "$LOCATION_OPERATION_ID" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | tail -n 1)
        if [ -z "$IN_PROGRESS_ID" ]; then
            echo "Failed to extract operation ID from error message"
            exit 1
        fi
        echo "Waiting for in-progress operation $IN_PROGRESS_ID to complete..."
        if ! wait_for_stackset_operation "LocationServiceStackSet" "$IN_PROGRESS_ID"; then
            echo "In-progress operation failed"
            exit 1
        fi
        # Retry the create operation
        LOCATION_OPERATION_ID=$(aws cloudformation create-stack-instances \
            --stack-set-name LocationServiceStackSet \
            --accounts "$ACCOUNT_ID" \
            --regions "$REGIONS_JSON" \
            --operation-preferences MaxConcurrentPercentage=100,FailureTolerancePercentage=0 \
            --profile "$aws_profile" \
            --query 'OperationId' \
            --output text)
    fi

    # Wait for the operation to complete
    echo "Waiting for Location Service API key deployment to complete..."
    if ! wait_for_stackset_operation "LocationServiceStackSet" "$LOCATION_OPERATION_ID"; then
        echo "Location Service API key deployment failed. Cleaning up..."
        
        # Delete stack instances
        aws cloudformation delete-stack-instances \
            --stack-set-name LocationServiceStackSet \
            --accounts "$ACCOUNT_ID" \
            --regions "$REGIONS_JSON" \
            --operation-preferences MaxConcurrentPercentage=100,FailureTolerancePercentage=0 \
            --no-retain-stacks \
            --profile "$aws_profile"
            
        # Wait for deletion to complete
        aws cloudformation wait stack-set-operation-complete \
            --stack-set-name LocationServiceStackSet \
            --profile "$aws_profile"
            
        # Delete the stack set
        aws cloudformation delete-stack-set \
            --stack-set-name LocationServiceStackSet \
            --profile "$aws_profile"
            
        echo "Cleanup completed. Deployment halted."
        exit 1
    fi

    # Create certificate stack in us-east-1 (required for API Gateway)
    echo "Creating/updating certificate stack in us-east-1..."
    aws cloudformation deploy \
        --template-file certificate-stack.yaml \
        --stack-name api-certificate-stack \
        --parameter-overrides \
            DomainName="$API_DOMAIN_NAME" \
            HostedZoneId="$HostedZoneId" \
        --region us-east-1 \
        --profile "$aws_profile"

    # Step 3: Create or update API Gateway StackSet template
    if ! aws cloudformation describe-stack-set --stack-set-name ApiGatewayStackSet --profile "$aws_profile" 2>/dev/null; then
        # Create new stack set if it doesn't exist
        aws cloudformation create-stack-set \
            --stack-set-name ApiGatewayStackSet \
            --template-body file://api-stackset.yaml \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --permission-model SELF_MANAGED \
            --administration-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AWSCloudFormationStackSetAdministrationRole" \
            --execution-role-name "AWSCloudFormationStackSetExecutionRole" \
            --parameters \
                ParameterKey=DomainName,ParameterValue="$API_DOMAIN_NAME" \
                ParameterKey=HostedZoneId,ParameterValue="$HostedZoneId" \
                ParameterKey=CORSOrigin,ParameterValue="$CORS_ORIGIN" \
            --profile "$aws_profile"
    else
        # Update existing stack set parameters if they've changed
        aws cloudformation update-stack-set \
            --stack-set-name ApiGatewayStackSet \
            --template-body file://api-stackset.yaml \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --administration-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AWSCloudFormationStackSetAdministrationRole" \
            --execution-role-name "AWSCloudFormationStackSetExecutionRole" \
            --parameters \
                ParameterKey=DomainName,ParameterValue="$API_DOMAIN_NAME" \
                ParameterKey=HostedZoneId,ParameterValue="$HostedZoneId" \
                ParameterKey=CORSOrigin,ParameterValue="$CORS_ORIGIN" \
            --profile "$aws_profile"
    fi

    # Step 4: Deploy API Gateway in each region with its corresponding API key
    for region in $DEPLOY_REGIONS; do
        echo "Setting up API Gateway in $region..."
        
        # Get the Location Service API key for this region
        echo "Retrieving Location Service API key for $region..."
        STACK_ID=$(aws cloudformation describe-stack-instance \
            --no-paginate \
            --stack-set-name LocationServiceStackSet \
            --stack-instance-account "$ACCOUNT_ID" \
            --stack-instance-region "$region" \
            --profile "$aws_profile" \
            --query 'StackInstance.StackId' --output text)
            
        # Wait for Location Service stack to complete and get API key
        echo "Waiting for Location Service stack to complete in $region..."
        STACK_ID=$(aws cloudformation describe-stack-instance \
            --stack-set-name LocationServiceStackSet \
            --stack-instance-account "$ACCOUNT_ID" \
            --stack-instance-region "$region" \
            --profile "$aws_profile" \
            --query 'StackInstance.StackId' --output text)
            
        # Wait for stack to complete and get stack ID
        echo "Stack ID for $region: $(aws cloudformation describe-stack-instance \
            --stack-set-name LocationServiceStackSet \
            --stack-instance-account "$ACCOUNT_ID" \
            --stack-instance-region "$region" \
            --profile "$aws_profile" \
            --query 'StackInstance.StackId' --output text)"
        
        # Get API key value using describe-key after stack creation
        API_KEY_VALUE=$(aws location describe-key \
            --key-name "DemoLocationApiKey" \
            --region "$region" \
            --profile "$aws_profile" \
            --query 'Key' \
            --output text)

        if [ -z "$API_KEY_VALUE" ]; then
            echo "Failed to retrieve API key for $region. Deployment halted."
            exit 1
        fi
        echo "API key retrieved for $region"

        # Deploy API Gateway stack instance with the verified API key
        echo "Deploying API Gateway in $region..."
        
        # Wait for any existing operations to complete first
        while true; do
            OPERATIONS=$(aws cloudformation list-stack-set-operations \
                --stack-set-name ApiGatewayStackSet \
                --query 'Summaries[?Status==`RUNNING`].OperationId' \
                --profile "$aws_profile" \
                --output text)
            if [ -z "$OPERATIONS" ]; then
                break
            fi
            echo "Waiting for existing operations to complete..."
            sleep 10
        done

        # Try to create stack instance first
        local api_operation_output
        api_operation_output=$(aws cloudformation create-stack-instances \
            --stack-set-name ApiGatewayStackSet \
            --accounts "$ACCOUNT_ID" \
            --regions "[\"$region\"]" \
            --parameter-overrides \
                ParameterKey=LocationApiKeyValue,ParameterValue="$API_KEY_VALUE" \
                ParameterKey=DomainName,ParameterValue="$API_DOMAIN_NAME" \
                ParameterKey=HostedZoneId,ParameterValue="$HostedZoneId" \
                ParameterKey=CORSOrigin,ParameterValue="$CORS_ORIGIN" \
            --operation-preferences MaxConcurrentPercentage=100,FailureTolerancePercentage=0 \
            --profile "$aws_profile" 2>&1)
            
        if [ $? -ne 0 ]; then
            if [[ $api_operation_output == *"StackInstanceAlreadyExistsException"* ]]; then
                # Stack instance exists, try to update it
                api_operation_output=$(aws cloudformation update-stack-instances \
                    --stack-set-name ApiGatewayStackSet \
                    --accounts "$ACCOUNT_ID" \
                    --regions "[\"$region\"]" \
                    --parameter-overrides \
                        ParameterKey=LocationApiKeyValue,ParameterValue="$API_KEY_VALUE" \
                        ParameterKey=DomainName,ParameterValue="$API_DOMAIN_NAME" \
                        ParameterKey=HostedZoneId,ParameterValue="$HostedZoneId" \
                        ParameterKey=CORSOrigin,ParameterValue="$CORS_ORIGIN" \
                    --operation-preferences MaxConcurrentCount=1,FailureToleranceCount=0 \
                    --profile "$aws_profile" 2>&1)
                # Stack instance doesn't exist, create it
                api_operation_output=$(aws cloudformation create-stack-instances \
                    --stack-set-name ApiGatewayStackSet \
                    --accounts "$ACCOUNT_ID" \
                    --regions "[\"$region\"]" \
                    --parameter-overrides \
                        ParameterKey=LocationApiKeyValue,ParameterValue="$API_KEY_VALUE" \
                        ParameterKey=DomainName,ParameterValue="$API_DOMAIN_NAME" \
                        ParameterKey=HostedZoneId,ParameterValue="$HostedZoneId" \
                        ParameterKey=CORSOrigin,ParameterValue="$CORS_ORIGIN" \
                    --operation-preferences MaxConcurrentCount=1,FailureToleranceCount=0 \
                    --profile "$aws_profile" 2>&1)
            elif [[ $api_operation_output == *"OperationInProgressException"* ]]; then
                # Extract operation ID from error message
                IN_PROGRESS_ID=$(echo "$api_operation_output" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | tail -n 1)
                if [ -n "$IN_PROGRESS_ID" ]; then
                    echo "Waiting for in-progress operation $IN_PROGRESS_ID to complete..."
                    if ! wait_for_stackset_operation "ApiGatewayStackSet" "$IN_PROGRESS_ID"; then
                        echo "In-progress operation failed"
                        return 1
                    fi
                    # Retry the create operation
                    api_operation_output=$(aws cloudformation create-stack-instances \
                        --stack-set-name ApiGatewayStackSet \
                        --accounts "$ACCOUNT_ID" \
                        --regions "[\"$region\"]" \
                        --parameter-overrides \
                            ParameterKey=LocationApiKeyValue,ParameterValue="$API_KEY_VALUE" \
                            ParameterKey=DomainName,ParameterValue="$API_DOMAIN_NAME" \
                            ParameterKey=HostedZoneId,ParameterValue="$HostedZoneId" \
                            ParameterKey=CORSOrigin,ParameterValue="$CORS_ORIGIN" \
                        --operation-preferences MaxConcurrentCount=1,FailureToleranceCount=0 \
                        --profile "$aws_profile" 2>&1)
                fi
            else
                echo "Failed to create stack instance: $api_operation_output"
                return 1
            fi
        fi
        
        API_OPERATION_ID=$(echo "$api_operation_output" | jq -r '.OperationId')
        if [ -z "$API_OPERATION_ID" ] || [ "$API_OPERATION_ID" = "null" ]; then
            echo "Failed to get operation ID from response"
            return 1
        fi

        # Wait for API Gateway stack instance to complete
        echo "Waiting for API Gateway stack instance to complete in $region..."
        echo "Operation ID: $API_OPERATION_ID"
        
        if ! wait_for_stackset_operation "ApiGatewayStackSet" "$API_OPERATION_ID"; then
            echo "Stack set operation failed in $region"
            return 1
        fi
    done

    # Set up DNS records for each region
    for region in $DEPLOY_REGIONS; do
        # Get stack instance outputs
        OUTPUTS=$(aws cloudformation describe-stack-instance \
            --no-paginate \
            --stack-set-name ApiGatewayStackSet \
            --stack-instance-account "$ACCOUNT_ID" \
            --stack-instance-region "$region" \
            --profile "$aws_profile" \
            --query 'StackInstance.StackId' --output text)

        REGIONAL_DOMAIN_NAME=$(aws cloudformation describe-stacks \
            --stack-name "$OUTPUTS" \
            --region "$region" \
            --profile "$aws_profile" \
            --query 'Stacks[0].Outputs[?OutputKey==`RegionalDomainName`].OutputValue' --output text)

        REGIONAL_HOSTED_ZONE_ID=$(aws cloudformation describe-stacks \
            --stack-name "$OUTPUTS" \
            --region "$region" \
            --profile "$aws_profile" \
            --query 'Stacks[0].Outputs[?OutputKey==`RegionalHostedZoneId`].OutputValue' --output text)

        # Fetch the Regional Domain Name using AWS CLI and AWS API Gateway's get-domain-names
        REGIONAL_DOMAIN_NAME=$(aws apigateway get-domain-names \
            --region "$region" \
            --profile "$aws_profile" \
            --query "items[?domainName=='$API_DOMAIN_NAME'].regionalDomainName" \
            --output text)
            
        if [ -z "$REGIONAL_DOMAIN_NAME" ]; then
            echo "Regional Domain Name could not be retrieved for $region. Skipping DNS update."
            continue
        fi
        echo "Regional Domain Name for $region: $REGIONAL_DOMAIN_NAME"

        # Dynamically set the HostedZoneId for API Gateway
        REGIONAL_HOSTED_ZONE_ID=$(get_hosted_zone_id "$region")

        if [[ -n "$REGIONAL_DOMAIN_NAME" ]] && [[ -n "$REGIONAL_HOSTED_ZONE_ID" ]] && [[ "$REGIONAL_HOSTED_ZONE_ID" != "Unknown" ]]; then
            # Create latency-based routing DNS record
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$HostedZoneId" \
                --change-batch '{
                    "Changes": [{
                        "Action": "UPSERT",
                        "ResourceRecordSet": {
                            "Name": "'"$API_DOMAIN_NAME"'",
                            "Type": "A",
                            "SetIdentifier": "'"$region"'",
                            "Region": "'"$region"'",
                            "AliasTarget": {
                                "HostedZoneId": "'"$REGIONAL_HOSTED_ZONE_ID"'",
                                "DNSName": "'"$REGIONAL_DOMAIN_NAME"'",
                                "EvaluateTargetHealth": false
                            }
                        }
                    }]
                }' \
                --profile "$aws_profile"

            echo "Updated DNS for latency-based routing for $region"
        else
            echo "Missing required outputs for DNS update in $region"
        fi
    done
}

# Removes all deployed infrastructure across specified regions using StackSets
#
# Performs the following cleanup:
# - Deletes CloudFormation StackSet instances in all regions
# - Removes Route53 DNS records for regional endpoints
# - Deletes the StackSet
#
# Global variables used:
#   DEPLOY_REGIONS - Space-separated list of target AWS regions
#   DOMAIN_NAME - Custom domain for API endpoints
#   HostedZoneId - Route53 hosted zone ID
#   aws_profile - AWS CLI profile name
delete_stacks() {

    # Convert space-separated regions to JSON array
    REGIONS_JSON="["
    for region in $DEPLOY_REGIONS; do
        REGIONS_JSON="$REGIONS_JSON\"$region\","
    done
    REGIONS_JSON="${REGIONS_JSON%,}]"

    # Get AWS account ID first
    local ACCOUNT_ID
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$aws_profile" --query 'Account' --output text)
    if [ -z "$ACCOUNT_ID" ]; then
        echo "Failed to get AWS account ID"
        return 1
    fi

    # Remove DNS records first
    for region in $DEPLOY_REGIONS; do
        # Get the record details
        RECORDS=$(aws route53 list-resource-record-sets \
            --hosted-zone-id "$HostedZoneId" \
            --profile "$aws_profile" \
            --query "ResourceRecordSets[?SetIdentifier=='$region' && Name=='$API_DOMAIN_NAME.']" \
            --output json)

        if [ -n "$RECORDS" ] && [ "$RECORDS" != "[]" ]; then
            # Extract the first record from the array and ensure it's properly formatted
            RECORD=$(echo "$RECORDS" | jq -c '.[0]')
            if [ -n "$RECORD" ] && [ "$RECORD" != "null" ]; then
                CHANGE_BATCH=$(jq -n \
                    --arg record "$RECORD" \
                    '{Changes:[{Action:"DELETE",ResourceRecordSet:($record|fromjson)}]}')
                aws route53 change-resource-record-sets \
                    --hosted-zone-id "$HostedZoneId" \
                    --change-batch "$CHANGE_BATCH" \
                    --profile "$aws_profile"
                echo "Deleted DNS record for $region"
            fi
        fi
    done

    # Delete API Gateway stack instances first
    aws cloudformation delete-stack-instances \
        --stack-set-name ApiGatewayStackSet \
        --accounts "[\"$ACCOUNT_ID\"]" \
        --regions "$REGIONS_JSON" \
        --operation-preferences MaxConcurrentCount=10,FailureToleranceCount=0 \
        --no-retain-stacks \
        --profile "$aws_profile"

    echo "Waiting for API Gateway stack instances to be deleted..."
    local api_operation_id
    api_operation_id=$(aws cloudformation list-stack-set-operations \
        --stack-set-name ApiGatewayStackSet \
        --profile "$aws_profile" \
        --query 'Summaries[0].OperationId' \
        --output text)
    
    if [ -n "$api_operation_id" ]; then
        wait_for_stackset_operation "ApiGatewayStackSet" "$api_operation_id"
    fi

    # Delete Location Service stack instances
    aws cloudformation delete-stack-instances \
        --stack-set-name LocationServiceStackSet \
        --accounts "[\"$ACCOUNT_ID\"]" \
        --regions "$REGIONS_JSON" \
        --operation-preferences MaxConcurrentCount=10,FailureToleranceCount=0 \
        --no-retain-stacks \
        --profile "$aws_profile"

    echo "Waiting for Location Service stack instances to be deleted..."
    local loc_operation_id
    loc_operation_id=$(aws cloudformation list-stack-set-operations \
        --stack-set-name LocationServiceStackSet \
        --profile "$aws_profile" \
        --query 'Summaries[0].OperationId' \
        --output text)
    
    if [ -n "$loc_operation_id" ]; then
        wait_for_stackset_operation "LocationServiceStackSet" "$loc_operation_id"
    fi

    # Wait a bit to ensure all stack instances are fully deleted
    sleep 30

    # Delete the stack sets
    aws cloudformation delete-stack-set \
        --stack-set-name ApiGatewayStackSet \
        --profile "$aws_profile" || true

    aws cloudformation delete-stack-set \
        --stack-set-name LocationServiceStackSet \
        --profile "$aws_profile" || true

    # Delete the StackSet roles
    echo "Removing StackSet roles..."
    aws cloudformation delete-stack \
        --stack-name stackset-execution-role \
        --profile "$aws_profile" \
        --region us-east-1 || true

    aws cloudformation delete-stack \
        --stack-name stackset-admin-role \
        --profile "$aws_profile" \
        --region us-east-1 || true

    # Wait for role stacks to be deleted
    aws cloudformation wait stack-delete-complete \
        --stack-name stackset-execution-role \
        --profile "$aws_profile" \
        --region us-east-1 || true

    aws cloudformation wait stack-delete-complete \
        --stack-name stackset-admin-role \
        --profile "$aws_profile" \
        --region us-east-1 || true

    # Delete the certificate stack
    echo "Deleting certificate stack..."
    aws cloudformation delete-stack \
        --stack-name api-certificate-stack \
        --profile "$aws_profile" \
        --region us-east-1

    aws cloudformation wait stack-delete-complete \
        --stack-name api-certificate-stack \
        --profile "$aws_profile" \
        --region us-east-1

    echo "StackSet and all instances have been deleted"
}

# Creates the required IAM roles for CloudFormation StackSet operations
#
# Creates:
# - AWSCloudFormationStackSetAdministrationRole
# - AWSCloudFormationStackSetExecutionRole
#
# Returns:
#   0 - Success
#   1 - Error creating roles
create_stackset_roles() {
    echo "Setting up StackSet IAM roles..."
    
    # Get AWS account ID
    local account_id=$(aws sts get-caller-identity --profile "$aws_profile" --query 'Account' --output text)
    if [ -z "$account_id" ]; then
        echo "Failed to get AWS account ID"
        return 1
    fi

    # Check if roles already exist
    local admin_role_exists=$(aws iam get-role --role-name AWSCloudFormationStackSetAdministrationRole --profile "$aws_profile" 2>/dev/null)
    local exec_role_exists=$(aws iam get-role --role-name AWSCloudFormationStackSetExecutionRole --profile "$aws_profile" 2>/dev/null)

    if [ -n "$admin_role_exists" ] && [ -n "$exec_role_exists" ]; then
        echo "StackSet IAM roles already exist"
        return 0
    fi

    # Use local template files
    local admin_template="stackset-admin-role.yml"
    local exec_template="stackset-exec-role.yml"
    
    if [ ! -f "$admin_template" ] || [ ! -f "$exec_template" ]; then
        echo "Required template files not found: $admin_template and/or $exec_template"
        return 1
    fi
    
    # Create the administration role if it doesn't exist
    if [ -z "$admin_role_exists" ]; then
        echo "Creating administration role..."
        if ! aws cloudformation deploy \
            --template-file "$admin_template" \
            --stack-name stackset-admin-role \
            --capabilities CAPABILITY_NAMED_IAM \
            --profile "$aws_profile" \
            --region us-east-1; then
            echo "Failed to create administration role"
            rm -f "$admin_template" "$exec_template"
            return 1
        fi
    fi

    # Create the execution role if it doesn't exist
    if [ -z "$exec_role_exists" ]; then
        echo "Creating execution role..."
        if ! aws cloudformation deploy \
            --template-file "$exec_template" \
            --stack-name stackset-execution-role \
            --capabilities CAPABILITY_NAMED_IAM \
            --parameter-overrides AdministratorAccountId="$account_id" \
            --profile "$aws_profile" \
            --region us-east-1; then
            echo "Failed to create execution role"
            rm -f "$admin_template" "$exec_template"
            return 1
        fi
    fi
        

    echo "StackSet IAM roles setup completed successfully"
    return 0
}

# Wait for a StackSet operation to complete
#
# Arguments:
#   $1 - StackSet name
#   $2 - Operation ID
#
# Returns:
#   0 - Operation succeeded
#   1 - Operation failed or was stopped
wait_for_stackset_operation() {
    local stackset_name=$1
    local operation_id=$2
    
    echo "Waiting for operation $operation_id to complete..."
    
    local max_attempts=60  # 30 minutes with 30-second sleep
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Get operation status with error handling
        local STATUS
        STATUS=$(aws cloudformation describe-stack-set-operation \
            --stack-set-name "$stackset_name" \
            --operation-id "$operation_id" \
            --profile "$aws_profile" \
            --query 'StackSetOperation.Status' \
            --output text 2>&1)
        
        local aws_exit_code=$?
        
        if [ $aws_exit_code -ne 0 ]; then
            echo "Error getting operation status: $STATUS"
            if [[ $STATUS == *"ValidationError"* ]]; then
                echo "Invalid operation ID format. Stopping operation check."
                return 1
            fi
            # For other errors, continue trying
            sleep 30
            ((attempt++))
            continue
        fi
        
        if [ -z "$STATUS" ]; then
            echo "Empty status received"
            sleep 30
            ((attempt++))
            continue
        fi
        
        echo "Current status: $STATUS"
        
        case "$STATUS" in
            SUCCEEDED)
                echo "Operation completed successfully"
                return 0
                ;;
            FAILED|STOPPED)
                # Get detailed error information
                local error_details
                error_details=$(aws cloudformation describe-stack-set-operation \
                    --stack-set-name "$stackset_name" \
                    --operation-id "$operation_id" \
                    --profile "$aws_profile" \
                    --query 'StackSetOperation.StatusReason' \
                    --output text)
                echo "Operation $STATUS: $error_details"
                
                # Get instance level errors
                local instance_errors
                instance_errors=$(aws cloudformation list-stack-set-operation-results \
                    --stack-set-name "$stackset_name" \
                    --operation-id "$operation_id" \
                    --profile "$aws_profile" \
                    --query 'Summaries[?Status==`FAILED`].[Account,Region,StatusReason]' \
                    --output text)
                
                if [ -n "$instance_errors" ]; then
                    echo "Stack instance errors:"
                    echo "$instance_errors"
                fi
                return 1
                ;;
            RUNNING|QUEUED|STOPPING)
                sleep 30
                ((attempt++))
                ;;
            *)
                echo "Unknown status: $STATUS"
                sleep 30
                ((attempt++))
                ;;
        esac
    done
    
    echo "Operation timed out after 30 minutes"
    return 1
}

# Validates required parameters and environment prerequisites
#
# Checks:
# - Required command line parameters are provided
# - CORS origin security implications
# - AWS CLI installation and availability
#
# Exits with status 1 if any validation fails
check_params(){
    # Check required parameters
    if [ -z "$API_DOMAIN_NAME" ]; then
        echo "Error: --api-domain parameter is required"
        echo "Usage: ./deploy.sh --api-domain <api-domain> --web-domain <web-domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ -z "$WEB_DOMAIN_NAME" ]; then
        echo "Error: --web-domain parameter is required"
        echo "Usage: ./deploy.sh --api-domain <api-domain> --web-domain <web-domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ -z "$HostedZoneId" ]; then
        echo "Error: --hosted-zone parameter is required"
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ -z "$CORS_ORIGIN" ]; then
        echo "Error: --cors parameter is required"
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ "$CORS_ORIGIN" == "*" ]; then
        echo "Warning: CORS origin '*' allows any origin to access the API. This could result in security vulnerabilities and high costs."
    fi

    # Check if the AWS CLI is installed
    if ! [ -x "$(command -v aws)" ]; then
        echo "AWS CLI is not installed. Please install the AWS CLI and configure it with the necessary permissions before running this script."
        exit 1
    fi

}

# Function to check if jq is installed
check_jq() {
    if ! [ -x "$(command -v jq)" ]; then
        echo "jq is not installed. Please install jq to run this script."
        exit 1
    fi
}

# Orchestrates the deployment or removal workflow
#
# Controls the execution flow based on --remove flag:
# - Validates parameters and prerequisites
# - Executes either deployment or removal process
# - Provides completion status
#
# Exit codes:
#   0 - Successful completion
#   1 - Error occurred during execution
main() {
    check_params
    check_jq

    if [[ "$REMOVE" == true ]]; then
        delete_stacks
        remove_website
        echo "Deletion completed successfully."
    else
        # Create StackSet roles if they don't exist
        if ! create_stackset_roles; then
            echo "Failed to create StackSet IAM roles. Deployment halted."
            exit 1
        fi
        
        deploy_website
        deployfunction
        if [ $? -eq 0 ]; then
            echo "Deployment completed successfully."
        else
            echo "Deployment failed. Please check the error messages above."
            exit 1
        fi
    fi
    exit 0
}

# Execute main function with all arguments
main
