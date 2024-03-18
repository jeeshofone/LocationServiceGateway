#!/bin/bash

# https://www.123cloud.st/p/regional-to-global-adapting-amazon
# Author: Will Laws
# Date: 2024-03-18

# Description:
# This script deploys the Geo Mapping Services and Geo API Services to the specified regions using AWS CLI
# The script assumes that the AWS CLI is installed and configured with the necessary permissions
# Please make sure to configure your AWS CLI with aws configure before running this script and use a profile with the necessary permissions

# Customize these variables based on your requirements
DOMAIN_NAME="geo.example.com" # Set this to the domain you wish to serve the GEO API from
CORS_ORIGIN="abcde12345.cloudfront.net" # Set this to your frontend domain - You can set this to "*" for testing. However, this will allow any origin to access the API, and could result in security vulnerabilities and high costs. Please set this to your frontend domain.
HostedZoneId="Z012345789ABCD" # Set this to the Hosted Zone ID of your domain
DEPLOY_REGIONS="us-east-1 ap-southeast-2" # Space-separated list of regions to deploy to. Make sure the regions are supported by AWS Location Service. The available list at the time of writing is below.
#us-east-2 us-east-1 us-west-2 ap-south-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 ca-central-1 eu-central-1 eu-west-1 eu-west-2 eu-north-1 sa-east-1

# The following regions are also supported for AWS GovCloud (US) customers and can be added to the DEPLOY_REGIONS list if required. however, you will need to update the Mapping section in the geo-services.yaml file to include the GovCloud region names and endpoints:
#us-gov-west-1 us-gov-west-1 us-gov-west-1

# take user input for --profile to set the aws profile when running the script
read -p "Enter the AWS CLI profile to use (default): " aws_profile
aws_profile=${aws_profile:-default}

# Function to fetch the Regional Domain Name and Hosted Zone ID for API Gateway
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

# Function to get the Hosted Zone ID for API Gateway based on the region
get_hosted_zone_id() {
    case "$1" in
        "us-east-2") echo "ZOJJZC49E0EPZ" ;;
        "us-east-1") echo "Z1UJRXOUMOOFQ8" ;;
        "us-west-1") echo "Z2MUQ32089INYE" ;;
        "us-west-2") echo "Z2OJLYMUO9EFXC" ;;
        "af-south-1") echo "Z2DHW2332DAMTN" ;;
        "ap-east-1") echo "Z3FD1VL90ND7K5" ;;
        "ap-south-1") echo "Z3VO1THU9YC4UR" ;;
        "ap-northeast-2") echo "Z20JF4UZKIW1U8" ;;
        "ap-southeast-1") echo "ZL327KTPIQFUL" ;;
        "ap-southeast-2") echo "Z2RPCDW04V8134" ;;
        "ap-northeast-1") echo "Z1YSHQZHG15GKL" ;;
        "ca-central-1") echo "Z19DQILCV0OWEC" ;;
        "eu-central-1") echo "Z1U9ULNL0V5AJ3" ;;
        "eu-west-1") echo "ZLY8HYME6SFDD" ;;
        "eu-west-2") echo "ZJ5UAJN8Y3Z2Q" ;;
        "eu-west-3") echo "Z3KY65QIEKYHQQ" ;;
        "eu-north-1") echo "Z3UWIKFBOOGXPP" ;;
        "eu-south-1") echo "Z3BT4WSQ9TDYZV" ;;
        "sa-east-1") echo "ZCMLWB8V5SYIT" ;;
        "me-south-1") echo "Z20ZBPC0SS8806" ;;
        "me-central-1") echo "Z08780021BKYYY8U0YHTV" ;;
        "us-gov-west-1") echo "Z1K6XKP9SAGWDV" ;;
        "us-gov-east-1") echo "Z3SE9ATJYCRCZJ" ;;
        *) echo "Unknown" ;;
    esac
}

# Function to deploy the Geo Mapping Services and Geo API Services to the specified regions using AWS CLI
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

# Function to delete the Geo Mapping Services and Geo API Services from the specified regions using AWS CLI
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

# Function to check if the required parameters are set and the AWS CLI is installed
check_params(){
    #check that the required parameters are set
    if [ -z "$DOMAIN_NAME" ]; then
        echo "DOMAIN_NAME is not set. Please set the DOMAIN_NAME variable to the domain you wish to serve the GEO API from."
        exit 1
    fi

    if [ -z "$HostedZoneId" ]; then
        echo "HostedZoneId is not set. Please set the HostedZoneId variable to the Hosted Zone ID of your domain."
        exit 1
    fi

    if [ -z "$CORS_ORIGIN" ]; then
        echo "CORS_ORIGIN is not set. Please set the CORS_ORIGIN variable to your frontend domain."
        exit 1
    fi

    if [ "$CORS_ORIGIN" == "*" ]; then
        read -p "CORS_ORIGIN is set to '*'. This will allow any origin to access the API, and could result in security vulnerabilities and high cost. Are you sure you want to continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment halted."
            exit 1
        fi
    fi

    # Check if the AWS CLI is installed
    if ! [ -x "$(command -v aws)" ]; then
        echo "AWS CLI is not installed. Please install the AWS CLI and configure it with the necessary permissions before running this script."
        exit 1
    fi

}

# Main function to handle user input and call the appropriate functions
main() {
    check_params

    case "$1" in
        --remove)
            delete_stacks
            echo "Deletion completed successfully."
            exit 0
            ;;
        *)
            deployfunction
            echo "Deployment completed successfully."
            exit 0
            ;;
    esac
}

main "$@"