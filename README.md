# Location Service Gateway Script

Automate the deployment of Amazon Location Services across specified AWS regions with this script. The script creates an API Gateway and integrates it with Location Services, specifying direct API Key references and CORS settings. It also creates an API key for accessing maps in Location Service, along with the map resource itself. This allows you to serve the Amazon Location Service API from a custom domain and deploy it across multiple regions. Users can access the API from a single endpoint domain name, and they will be directed to the backend services in the closest region, ensuring low-latency, high-quality, and cost-effective map tile delivery, worldwide.

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

Customize the following variables in the script as per your requirements:

- `DOMAIN_NAME`: The domain name to serve the GEO API from. (Note: This domain should be registered and available in AWS Route 53.)
- `CORS_ORIGIN`: Your frontend domain. (Note: For testing, you can set this to "*", but it's recommended to specify your frontend domain for security purposes.)
- `HostedZoneId`: The Hosted Zone ID of your domain. 
- `DEPLOY_REGIONS`: A space-separated list of regions where you wish to deploy the services. Ensure these regions support AWS Location Service. The deploy.sh file has a list of regions where AWS Location Service is available. You can add or remove regions as per your requirements.

## Usage

To deploy the services, simply run the script and provide the AWS CLI profile you wish to use when prompted:

```bash
./deploy.sh
```

When done cleaning up, you can remove the deployed stacks and DNS records. Run the script with the `--remove` flag and provide the AWS CLI profile when prompted:
```bash
./deploy.sh --remove
```

## CloudFormation Templates

The script utilizes `geo-api.yaml` and `geo-services.yaml` CloudFormation templates:

- `geo-api.yaml`: Configures the API Gateway and integrates it with Location Services, specifying direct API Key references and CORS settings.
- `geo-services.yaml`: Creates an API key for accessing maps in Location Service, along with the map resource itself.

## Architecture Diagram

Image: [Location Service Gateway](diagram.png)
![alt text](https://github.com/jeeshofone/LocationServiceGateway/blob/main/diagram.png?raw=true)

Ensure you have the necessary permissions and meet all prerequisites before running the script or deploying the CloudFormation templates.
