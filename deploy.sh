#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

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
#   ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]

# Default values
DOMAIN_NAME=""
CORS_ORIGIN=""
HostedZoneId=""
S3_BUCKET_NAME=""
aws_profile="default"
DEPLOY_REGIONS="us-east-1 ap-southeast-2"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN_NAME="$2"
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
        --stack-name WebsiteStack \
        --region us-east-1 \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            DomainName=$DOMAIN_NAME \
            S3BucketName=$S3_BUCKET_NAME \
            HostedZoneId=$HostedZoneId

    echo "Website infrastructure deployed"
}

# Remove the S3/CloudFront website infrastructure
remove_website() {
    echo "Removing website infrastructure..."
    
    # Empty the S3 bucket first
    aws s3 rm s3://$S3_BUCKET_NAME --recursive --profile "$aws_profile"
    
    # Delete the CloudFormation stack
    aws cloudformation delete-stack \
        --profile "$aws_profile" \
        --stack-name WebsiteStack \
        --region us-east-1
    
    aws cloudformation wait stack-delete-complete \
        --profile "$aws_profile" \
        --stack-name WebsiteStack \
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
    # Make sure the user is aware that the script will deploy to the specified regions and prompt for confirmation
    echo "This script will deploy the Geo Mapping Services and Geo API Services to the specified regions using CloudFormation StackSets."
    echo "Those regions are: $DEPLOY_REGIONS"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo 
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment halted."
        exit 1
    fi

    # Convert space-separated regions to JSON array for AWS CLI
    REGIONS_JSON="["
    for region in $DEPLOY_REGIONS; do
        REGIONS_JSON="$REGIONS_JSON\"$region\","
    done
    REGIONS_JSON="${REGIONS_JSON%,}]"

    # Create StackSet
    aws cloudformation create-stack-set \
        --stack-set-name GeoServicesStackSet \
        --template-body file://stackset-template.yaml \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --permission-model SELF_MANAGED \
        --parameters ParameterKey=DomainName,ParameterValue=$DOMAIN_NAME \
                    ParameterKey=HostedZoneId,ParameterValue=$HostedZoneId \
                    ParameterKey=CORSOrigin,ParameterValue=$CORS_ORIGIN \
        --profile "$aws_profile"

    # Create stack instances in all regions
    aws cloudformation create-stack-instances \
        --stack-set-name GeoServicesStackSet \
        --accounts "[$(aws sts get-caller-identity --query 'Account' --output text)]" \
        --regions "$REGIONS_JSON" \
        --operation-preferences MaxConcurrentCount=10,FailureToleranceCount=0 \
        --profile "$aws_profile"

    # Wait for stack instances to complete
    echo "Waiting for stack instances to complete..."
    aws cloudformation wait stack-set-operation-complete \
        --stack-set-name GeoServicesStackSet \
        --profile "$aws_profile"

    # Set up DNS records for each region
    for region in $DEPLOY_REGIONS; do
        # Get stack instance outputs
        OUTPUTS=$(aws cloudformation describe-stack-instance \
            --stack-set-name GeoServicesStackSet \
            --stack-instance-account $(aws sts get-caller-identity --query 'Account' --output text) \
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

        # Create latency-based routing DNS record
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$HostedZoneId" \
            --change-batch '{
                "Changes": [{
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": "'"$DOMAIN_NAME"'",
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
    echo "This script will delete the Geo Services StackSet from all regions."
    echo "Those regions are: $DEPLOY_REGIONS"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo 
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deletion halted."
        exit 1
    fi

    # Convert space-separated regions to JSON array
    REGIONS_JSON="["
    for region in $DEPLOY_REGIONS; do
        REGIONS_JSON="$REGIONS_JSON\"$region\","
    done
    REGIONS_JSON="${REGIONS_JSON%,}]"

    # Remove DNS records first
    for region in $DEPLOY_REGIONS; do
        RECORD=$(aws route53 list-resource-record-sets \
            --hosted-zone-id "$HostedZoneId" \
            --profile "$aws_profile" \
            --query "ResourceRecordSets[?SetIdentifier=='$region']" \
            --output text)

        if [[ -n "$RECORD" ]]; then
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$HostedZoneId" \
                --change-batch '{
                    "Changes": [{
                        "Action": "DELETE",
                        "ResourceRecordSet": '"$RECORD"'
                    }]
                }' \
                --profile "$aws_profile"
            echo "Deleted DNS record for $region"
        fi
    done

    # Delete stack instances
    aws cloudformation delete-stack-instances \
        --stack-set-name GeoServicesStackSet \
        --accounts "[$(aws sts get-caller-identity --query 'Account' --output text)]" \
        --regions "$REGIONS_JSON" \
        --operation-preferences MaxConcurrentCount=10,FailureToleranceCount=0 \
        --no-retain-stacks \
        --profile "$aws_profile"

    # Wait for stack instance deletion
    echo "Waiting for stack instances to be deleted..."
    aws cloudformation wait stack-set-operation-complete \
        --stack-set-name GeoServicesStackSet \
        --profile "$aws_profile"

    # Delete the stack set
    aws cloudformation delete-stack-set \
        --stack-set-name GeoServicesStackSet \
        --profile "$aws_profile"

    echo "StackSet and all instances have been deleted"
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
    if [ -z "$DOMAIN_NAME" ]; then
        echo "Error: --domain parameter is required"
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ -z "$HostedZoneId" ]; then
        echo "Error: --hosted-zone parameter is required"
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ -z "$CORS_ORIGIN" ]; then
        echo "Error: --cors parameter is required"
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> --bucket <bucket> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ -z "$S3_BUCKET_NAME" ]; then
        echo "Error: --bucket parameter is required"
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> --bucket <bucket> [--profile <profile>] [--remove]"
        exit 1
    fi

    if [ "$CORS_ORIGIN" == "*" ]; then
        read -p "Warning: CORS origin '*' allows any origin to access the API. This could result in security vulnerabilities and high costs. Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 1
        fi
    fi

    # Check if the AWS CLI is installed
    if ! [ -x "$(command -v aws)" ]; then
        echo "AWS CLI is not installed. Please install the AWS CLI and configure it with the necessary permissions before running this script."
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

    if [[ "$REMOVE" == true ]]; then
        delete_stacks
        remove_website
        echo "Deletion completed successfully."
    else
        deploy_website
        deployfunction
        echo "Deployment completed successfully."
    fi
    exit 0
}

# Execute main function with all arguments
main
