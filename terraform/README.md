# Snow Resorts — AWS Infrastructure (Terraform)

Infrastructure-as-Code for the **Snow Resorts** app. Everything lives under
`terraform/` in the `snow-resorts-infra` repo and is fully self-contained.

> Development runs 100% local (Docker Compose, `$0`). Terraform is **only** for
> the two AWS environments: `staging` (cost-optimized beta) and `prod` (full
> architecture). Never develop directly against AWS.

## Architecture at a glance

Single **ALB** (path-based routing, no API Gateway) → 5 **Fargate** services
discovered via **Cloud Map / ECS Service Connect** → **1 RDS PostgreSQL 16**
(schemas per service, not 5 instances) + **ElastiCache Redis** + **S3/CloudFront**,
protected by **WAF**. Auth is the app's own JWT auth-service (no Cognito).

ALB routing table (prod):

```
/snow-resort-service/v1/auth/*        → auth-service
/snow-resort-service/v1/users/*       → user-service
/snow-resort-service/v1/friends/*     → user-service
/snow-resort-service/v1/resorts/*     → resort-service
/snow-resort-service/v1/location/*    → location-service
/ws/*                                 → location-service   (sticky sessions for WebSocket)
/snow-resort-service/v1/runs/*        → activity-service
/snow-resort-service/v1/leaderboard/* → activity-service
```

### Unified Swagger UI (prod/staging)

Locally (`snow-resorts-infra/docker`) a single Swagger UI is served at
`http://localhost:8080/swagger/` with a dropdown of all 5 services, each loading
`/api-docs/<service>` (proxied to that service's `/v3/api-docs`). To mirror this on AWS:

```
/swagger, /swagger/*   → swagger-ui task        (swaggerapi/swagger-ui, BASE_URL=/swagger)
/api-docs/<service>    → <service> /v3/api-docs  (one rule per service)
```

Caveat: **the ALB does path-pattern routing but no path rewriting**, so `/api-docs/auth`
cannot be transparently rewritten to `/v3/api-docs` at the ALB. Two options for prod:

1. Run `swaggerapi/swagger-ui` as a tiny dedicated task behind a `docs` target group and
   front the `/api-docs/*` proxying with a small nginx/sidecar (same `nginx.conf` shape as
   local) — keeps the local design 1:1.
2. Or set each service's `springdoc.api-docs.path` to `/api-docs/<service>` so the ALB can
   route those paths directly to the owning service with no rewrite.

The path patterns above are documented in `envs/prod/main.tf` and `envs/staging/main.tf`
(commented next to the live `routing_rules`) so they can be enabled once a `docs` target
group / swagger-ui task is provisioned.

## Layout

```
infra/terraform/
├── modules/
│   ├── vpc/            # subnets, optional NAT, S3 gateway + interface endpoints
│   ├── rds/            # PostgreSQL 16 (+PostGIS via Flyway), KMS, Multi-AZ toggle
│   ├── ecs/            # Fargate cluster, 1..N services, Service Connect, task roles
│   ├── alb/            # single ALB, target groups, path routing, WSS stickiness
│   ├── redis/          # ElastiCache replication group
│   ├── s3-cloudfront/  # assets/avatars/map-packages/tracks buckets + CloudFront
│   └── waf/            # WAFv2 (Common Rule Set + rate limit) + ALB association
└── envs/
    ├── staging/        # cost-optimized (~$42-55/mo)
    └── prod/           # full architecture (~$120-200/mo)
```

## Prerequisites

- Terraform `>= 1.5`, AWS provider `~> 5.40`.
- AWS credentials via environment/SSO/role — **never** hardcode keys. The code
  contains no credentials or secrets; DB/JWT secrets are generated at apply time
  and stored in SSM (staging) / Secrets Manager (prod).
- A one-time remote-state backend: an S3 bucket + a DynamoDB lock table.

### Create the state backend once

```bash
aws s3api create-bucket --bucket snow-resorts-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket snow-resorts-tfstate \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name snow-resorts-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

State keys are per-environment (`staging/terraform.tfstate`, `prod/terraform.tfstate`),
so the same bucket safely holds both. No workspaces required.

## Applying an environment

```bash
cd envs/staging        # or envs/prod

terraform init \
  -backend-config="bucket=snow-resorts-tfstate" \
  -backend-config="key=staging/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=snow-resorts-tflock" \
  -backend-config="encrypt=true"

cp terraform.tfvars.example terraform.tfvars   # then edit (image URIs, cert, emails)

terraform plan
terraform apply
```

Push container images to ECR and set `app_image` (staging) /
`service_images` (prod) before applying, otherwise the services run the
placeholder busybox image and fail health checks.

### Local validation (no AWS credentials)

```bash
terraform fmt -recursive
terraform init -backend=false && terraform validate   # per module and per env
```

## Environment differences & cost

| Component        | staging (~$42-55/mo)                              | prod (~$120-200/mo)                          |
|------------------|--------------------------------------------------|----------------------------------------------|
| Networking       | Public subnets, **no NAT** (−$32)                | 2 AZs, **1 NAT** + interface endpoints       |
| Compute          | **1 Fargate task** (all services in 1 JVM)       | **5 Fargate services**, resort on Spot       |
| RDS              | `db.t4g.micro` Single-AZ, 20 GB                  | `db.t4g.small` **Multi-AZ**, 30 GB gp3       |
| Redis            | **Skipped** (in-memory fanout)                   | `cache.t4g.micro`                            |
| ALB              | 1 ALB, all paths → app TG (sticky)               | 1 ALB, 5 target groups, path routing         |
| WAF              | **Skipped**                                      | Common Rule Set + 2000 req/5min rate limit   |
| CloudFront       | **Skipped** (presigned S3 URLs)                  | CloudFront in front of CDN buckets           |
| Secrets          | **SSM Parameter Store** (free)                   | **Secrets Manager** (RDS password rotated)   |
| Encryption       | SSE-S3 (AES256)                                  | SSE-KMS (customer key) + RDS KMS             |
| Budgets          | —                                                | AWS Budgets at **$150** and **$200**         |

### Cost-saving choices (per the AWS rule)

- **1 ALB, not 5** — path routing saves ~$64/mo.
- **1 RDS with schemas, not 5 instances** — schemas (`auth`, `users`, `resorts`,
  `location`, `activity`) are created by Flyway, not Terraform.
- **S3 Gateway VPC endpoint** (free) in both envs; **ECR/Logs/Secrets/SSM
  interface endpoints** in prod to cut NAT traffic.
- **Fargate Spot** for `resort-service` (read-heavy, interruption-tolerant).
- **Single NAT Gateway** in prod (shared across AZs).

## Notes & follow-ups

- **PostGIS** is enabled per schema by the services' first Flyway migration
  (`CREATE EXTENSION postgis;`). RDS for PostgreSQL supports it natively.
- **TimescaleDB is NOT available on standard RDS PostgreSQL.** The architecture
  plan references it for `activity.gps_points`; on RDS use native time-based
  partitioning, or move that workload to Aurora/self-managed if TimescaleDB is
  required. This is called out in `modules/rds/main.tf`.
- **JWT secret rotation**: the RDS master password rotates automatically
  (RDS-managed secret). The JWT secret is stored in Secrets Manager but needs a
  rotation Lambda to auto-rotate — attach `aws_secretsmanager_secret_rotation`
  once a rotation function exists.
- **HTTPS**: provide `certificate_arn` (ACM) to enable the TLS 1.3 listener and
  HTTP→HTTPS redirect. Without it the ALB serves plain HTTP:80 (acceptable only
  for a closed staging beta).
- `terraform apply` is intentionally **not** run here; review the plan first.
