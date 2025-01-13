# Location Service Gateway with Static Website Hosting

This project automates the deployment of Amazon Location Services across specified AWS regions with CloudFront-enabled static website hosting. The solution creates an API Gateway integrated with Location Services (with API Key references and CORS settings) and sets up S3/CloudFront infrastructure for hosting the map interface. Users can access both the map interface and API endpoints through custom domains, with backend services automatically routing to the closest region for optimal performance.

## Overview

Building on the experience from developing [findyourfivepm.com](https://findyourfivepm.com), this script solves a crucial challenge: ensuring low-latency, high-quality, and cost-effective map tile delivery worldwide. Amazon Location Service (ALS) was chosen for its robust features but required an innovative approach to overcome regional latency when serving map tiles. 

For an in-depth exploration of this project's conception, challenges, and the decision-making process, see my detailed blog post: [Regional to Global - Adapting Amazon Location Service for Worldwide Use](https://www.123cloud.st/p/regional-to-global-adapting-amazon).

### Prerequisites

Before running this script, ensure that you have executed `aws configure` to set up your CLI with access keys, secret keys, and default region information. Please use a profile that has permissions to create resources specified in the script. My preference is to use AWS SSO to manage multiple accounts and roles. 

IMPORTANT: ensure that you are in the right AWS account before running the script. You can verify this by running the following command:

```bash
aws sts get-caller-identity --profile <your-profile>
```

You will need a domain name and a Hosted Zone ID for the domain to serve the API from. The domain name should be a registered domain, and the Hosted Zone ID should be available in the AWS Route 53 service. You can use a domain registered with AWS Route 53 or a domain registered with another registrar as long as the Hosted Zone ID is available in AWS Route 53.

## Configuration

The solution requires configuration for both the API Gateway and static website hosting:

### API Gateway Configuration
- `DOMAIN_NAME`: Domain name for the GEO API (must be registered in Route 53)
- `CORS_ORIGIN`: Frontend domain for CORS (use "*" for testing only)
- `HostedZoneId`: Route 53 Hosted Zone ID
- `DEPLOY_REGIONS`: Space-separated list of deployment regions (must support Location Service)

### Website Hosting Configuration
- A separate domain name for the static website
- S3 bucket name for content storage
- Route 53 Hosted Zone ID for the website domain

## Usage

### Deploy Using deploy.sh Script

The `deploy.sh` script automates the deployment of both the API Gateway/Location Services and the static website hosting infrastructure:

```bash
./deploy.sh \
  --domain api.yourdomain.com \
  --hosted-zone Z012345789ABCD \
  --cors map.yourdomain.com \
  --bucket your-bucket-name \
  --profile your-aws-profile
```

Parameters:
- `--domain`: Domain name for the API Gateway
- `--hosted-zone`: Route 53 hosted zone ID
- `--cors`: Allowed CORS origin domain
- `--bucket`: S3 bucket name for static website hosting
- `--profile`: AWS CLI profile name (optional, defaults to 'default')

The script will:
1. Deploy the S3/CloudFront infrastructure for website hosting
2. Create Location Service API keys in each region
3. Deploy API Gateway with the retrieved API keys
4. Configure Route53 for latency-based routing

You can verify your AWS profile before running the script:
```bash
aws sts get-caller-identity --profile your-aws-profile
```

### Deploy Static Website
```bash
aws cloudformation deploy \
  --template-file s3-cloudfront.yaml \
  --stack-name map-website \
  --parameter-overrides \
    DomainName=map.yourdomain.com \
    S3BucketName=your-bucket-name \
    HostedZoneId=Z012345789ABCD \
  --capabilities CAPABILITY_IAM
```

### Cleanup

To remove all deployed resources, use the `--remove` flag with the same parameters:

```bash
./deploy.sh \
  --domain api.yourdomain.com \
  --hosted-zone Z012345789ABCD \
  --cors map.yourdomain.com \
  --bucket your-bucket-name \
  --profile your-aws-profile \
  --remove
```

The script will:
1. Remove API Gateway and Location Services StackSets
2. Delete the S3 bucket contents
3. Remove the CloudFront distribution
4. Clean up all associated resources

## CloudFormation Templates

The solution uses multiple CloudFormation templates:

- `location-stackset.yaml`: Location Service API key creation (deployed as StackSet)
- `api-stackset.yaml`: API Gateway configuration with Location Services integration (deployed as StackSet)
- `s3-cloudfront.yaml`: S3 bucket and CloudFront distribution for static website hosting

## Architecture Diagram

Image: [Location Service Gateway](diagram.png)
![alt text](https://github.com/jeeshofone/LocationServiceGateway/blob/main/diagram.png?raw=true)

Ensure you have the necessary permissions and meet all prerequisites before running the script or deploying the CloudFormation templates.
