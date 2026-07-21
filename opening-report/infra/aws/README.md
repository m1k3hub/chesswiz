# scidb-beta AWS Deployment

This Terraform configuration deploys the full scidb-beta stack on AWS:

| Component | Service | Purpose |
|-----------|---------|---------|
| SPA | S3 + CloudFront | Static React app served globally |
| API adapter | ECS/Fargate + ALB | `runtime_adapter.py` container |
| Database files | EFS + S3 | Shared filesystem + object storage for imports/exports |
| Job queues | SQS | Background jobs (imports, reports, maintenance, exports) |
| Event bus | ElastiCache Redis | Job progress events + short-lived workspace state |
| Metadata | RDS PostgreSQL | Users, permissions, job records, database metadata |

## Prerequisites

1. **AWS CLI** configured with credentials that have permission to create the resources above.
2. **Terraform** >= 1.5 installed.
3. **Docker** to build and push the runtime adapter image.
4. An ECR repository (or any container registry) for the adapter image.

## Deploy steps

```bash
cd infra/aws/terraform

# 1. Initialize Terraform
terraform init

# 2. Review the plan
terraform plan -var="adapter_image=<your-registry>/scidb-beta-adapter:latest"

# 3. Apply
terraform apply -var="adapter_image=<your-registry>/scidb-beta-adapter:latest"
```

## Deploying the SPA

After `terraform apply`, upload the built SPA to the S3 bucket:

```bash
cd ../../..  # back to opening-report/
npm run build
aws s3 sync dist/ s3://$(terraform -chdir=infra/aws/terraform output -raw spa_s3_bucket)/ --delete
```

The CloudFront distribution URL is available via:

```bash
terraform -chdir=infra/aws/terraform output cloudfront_distribution_domain
```

## Building and pushing the adapter image

```bash
docker build -t scidb-beta-adapter .
docker tag scidb-beta-adapter:latest <your-registry>/scidb-beta-adapter:latest
docker push <your-registry>/scidb-beta-adapter:latest
```

Then update the ECS service:

```bash
aws ecs update-service --cluster scidb-beta-prod-cluster --service scidb-beta-prod-adapter --force-new-deployment
```

## Environment variables passed to the adapter

The ECS task definition injects:

| Variable | Value |
|----------|-------|
| `REDIS_URL` | `redis://<elasticache-endpoint>:6379` |
| `S3_BUCKET` | `<artifacts-bucket-name>` |
| `S3_REGION` | `us-east-1` (or configured region) |
| `DATA_DIR` | `/app/data` (EFS mount) |

## Customization

Edit `variables.tf` or pass `-var` flags:

```bash
terraform apply \
  -var="aws_region=eu-west-1" \
  -var="ecs_desired_count=3" \
  -var="db_instance_class=db.t3.small" \
  -var="adapter_image=my-registry/scidb-beta-adapter:v1.2"
```

## Cleanup

```bash
terraform destroy
```

> **Warning:** `terraform destroy` will delete the RDS database and all S3
> artifacts. Back up any important data first.