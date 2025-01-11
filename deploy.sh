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

# Deploys geo mapping services and API infrastructure across specified regions
#
# Performs the following operations:
# - Deploys CloudFormation stacks for geo mapping services
# - Creates and configures API keys
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
    echo "This script will deploy the Geo Mapping Services and Geo API Services to the specified regions using AWS CLI."
    echo "Those regions are: $DEPLOY_REGIONS"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo 
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment halted."
        exit 1
    fi

    # Loop through the specified regions for deployment
    for region in $DEPLOY_REGIONS; do
        echo "Deploying to $region"
        aws cloudformation deploy --profile "$aws_profile" --template-file geo-services.yaml --stack-name GeoMappingServicesStack --region $region --capabilities CAPABILITY_NAMED_IAM --parameter-overrides CORSOrigin=$CORS_ORIGIN UpdateTimestamp=$(date +%s)

        # Fetch the API Key value using AWS CLI and AWS Location Service's describe-key
        API_KEY_VALUE=$(aws location describe-key --profile "$aws_profile" --key-name DemoLocationApiKey --region $region --query 'Key' --output text)
        echo "API Key Value for $region: $API_KEY_VALUE"

        # Check if API_KEY_VALUE is successfully retrieved; if not, halt the process
        if [ -z "$API_KEY_VALUE" ]; then
            echo "API Key Value could not be retrieved. Deployment halted."
            exit 1
        fi

        # Deploy geo-api.yaml with the retrieved API Key value
        aws cloudformation deploy --profile "$aws_profile" --template-file geo-api.yaml --stack-name GeoAPIServicesStack --region $region --capabilities CAPABILITY_NAMED_IAM --parameter-overrides ApiKeyValue=$API_KEY_VALUE DomainName=$DOMAIN_NAME HostedZoneId=${HostedZoneId} CORSOrigin=${CORS_ORIGIN} UpdateTimestamp=$(date +%s)

        # Fetch the Regional Domain Name using AWS CLI and AWS API Gateway's get-domain-names
        REGIONAL_DOMAIN_NAME=$(aws apigateway get-domain-names --region $region --profile "$aws_profile" --query "items[?domainName=='$DOMAIN_NAME'].regionalDomainName" --output text)
        if [ -z "$REGIONAL_DOMAIN_NAME" ]; then
            echo "Regional Domain Name could not be retrieved. Deployment halted."
            exit 1
        fi
        echo "Regional Domain Name for $region: $REGIONAL_DOMAIN_NAME"

        # Dynamically set the HostedZoneId for API Gateway
        REGIONAL_HOSTED_ZONE_ID=$(get_hosted_zone_id "$region")
        if [[ -z "$REGIONAL_HOSTED_ZONE_ID" ]] || [[ -z "$REGIONAL_DOMAIN_NAME" ]]; then
            echo "Missing information for $region; skipping DNS update."
            continue
        fi

        # Creating latency-based routing DNS record
        aws route53 change-resource-record-sets --region us-east-1 --profile "$aws_profile" --hosted-zone-id "$HostedZoneId" --change-batch '{
            "Changes": [{
                "Action": "UPSERT",
                "ResourceRecordSet": {
                "Name": "'"$DOMAIN_NAME"'",
                "Type": "A",
                "SetIdentifier": "'$region'",
                "Region": "'$region'",
                "AliasTarget": {
                    "HostedZoneId": "'$REGIONAL_HOSTED_ZONE_ID'",
                    "DNSName": "'$REGIONAL_DOMAIN_NAME'",
                    "EvaluateTargetHealth": false
                }
                }
            }]}'
        echo "Updated DNS for latency-based routing for $region."
    done
}

# Removes all deployed infrastructure across specified regions
#
# Performs the following cleanup:
# - Deletes CloudFormation stacks in each region
# - Removes Route53 DNS records for regional endpoints
# - Waits for stack deletion completion
#
# Global variables used:
#   DEPLOY_REGIONS - Space-separated list of target AWS regions
#   DOMAIN_NAME - Custom domain for API endpoints
#   HostedZoneId - Route53 hosted zone ID
#   aws_profile - AWS CLI profile name
delete_stacks() {
    # Make sure the user is aware that the script will deploy to the specified regions and prompt for confirmation
    echo "This script will delete the Geo Mapping Services and Geo API Services to the specified regions using AWS CLI."
    echo "Those regions are: $DEPLOY_REGIONS"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo 
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment halted."
        exit 1
    fi

    echo "Removing the stacks from the specified regions"
    for region in $DEPLOY_REGIONS; do
        if fetch_regional_domain_and_hosted_zone "$region" "$aws_profile"; then 
            # Only proceed if the function was successful
            echo "Removing stacks from $region"
            aws cloudformation delete-stack --profile "$aws_profile" --stack-name GeoMappingServicesStack --region $region
            aws cloudformation wait stack-delete-complete --profile "$aws_profile" --stack-name GeoMappingServicesStack --region $region
            aws cloudformation delete-stack --profile "$aws_profile" --stack-name GeoAPIServicesStack --region $region
            aws cloudformation wait stack-delete-complete --profile "$aws_profile" --stack-name GeoAPIServicesStack --region $region

            # Fetch and delete DNS record for $region
            RECORD=$(aws route53 list-resource-record-sets --profile "$aws_profile" --hosted-zone-id "$HostedZoneId" \
            | jq -r ".ResourceRecordSets[] | select(.Name==\"$DOMAIN_NAME.\" and .Region==\"$region\")")

            if [[ -n "$RECORD" ]]; then
                aws route53 change-resource-record-sets --region us-east-1 --profile "$aws_profile" --hosted-zone-id "$HostedZoneId" --change-batch '{
                    "Changes": [{
                        "Action": "DELETE",
                        "ResourceRecordSet": {
                        "Name": "'"$DOMAIN_NAME"'",
                        "Type": "A",
                        "SetIdentifier": "'$region'",
                        "Region": "'$region'",
                        "AliasTarget": {
                            "HostedZoneId": "'$REGIONAL_HOSTED_ZONE_ID'",
                            "DNSName": "'$REGIONAL_DOMAIN_NAME'",
                            "EvaluateTargetHealth": false
                        }
                        }
                    }]}'

                echo "Deleted DNS record for $region - $DOMAIN_NAME in $HostedZoneId for $HOSTED_ZONE_ID"
            else
                echo "No matching DNS record found for $region - $DOMAIN_NAME."
            fi
        else
            echo "Skipping cleanup for $region due to missing information."
        fi
    done
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
        echo "Usage: ./deploy.sh --domain <domain> --hosted-zone <zone-id> --cors <origin> [--profile <profile>] [--remove]"
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
        echo "Deletion completed successfully."
    else
        deployfunction
        echo "Deployment completed successfully."
    fi
    exit 0
}

# Execute main function with all arguments
main
