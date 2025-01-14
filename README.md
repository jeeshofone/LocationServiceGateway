# Location Service Gateway with Static Website Hosting

This project automates the deployment of Amazon Location Services across multiple AWS regions with CloudFront-enabled static website hosting. The solution:

1. Deploys a static website using S3 and CloudFront to host the map interface
2. Creates Location Service API keys in each specified region
3. Deploys API Gateway with Location Service integration in each region
4. Sets up latency-based DNS routing for optimal performance

The end result is a globally distributed map interface that users can access through custom domains, with API requests automatically routed to the nearest region.

## Overview

This solution addresses the challenge of serving map tiles with low latency worldwide using Amazon Location Service (ALS). While ALS provides robust mapping capabilities, it is region-specific. This implementation:

1. Uses CloudFront to serve the static website content globally
2. Creates regional API Gateways that proxy requests to ALS
3. Implements latency-based routing to direct users to the nearest region
4. Manages API keys and CORS settings across regions

The architecture ensures optimal performance by serving map tiles from the closest available region while maintaining a single global endpoint for the API.

### Prerequisites

1. AWS CLI configured with appropriate credentials:
   ```bash
   aws configure
   ```
   
2. Required permissions to create:
   - CloudFormation StackSets
   - S3 buckets
   - CloudFront distributions
   - API Gateway
   - Location Service resources
   - Route 53 records
   - IAM roles

3. Two domain names registered in Route 53:
   - One for the API Gateway (e.g., geo.example.com)
   - One for the website (e.g., maps.example.com)

4. Route 53 hosted zone ID for your domain

Verify your AWS account access:
```bash
aws sts get-caller-identity --profile <your-profile>
```

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
  --api-domain api.yourdomain.com \
  --web-domain map.yourdomain.com \
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
