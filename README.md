# snow-resorts-infra

Infrastructure for the Snow Resorts platform:

| Path | Purpose |
|------|---------|
| [`terraform/`](terraform/) | AWS IaC — reusable modules + `staging` (~$50/mo) and `prod` (~$120–200/mo) environments. See [`terraform/README.md`](terraform/README.md) |
| [`docker/`](docker/) | Local dev stack ($0): Postgres+PostGIS, Redis, MinIO, nginx gateway (:8080) + unified Swagger UI |
| [`scripts/`](scripts/) | `seed.sh` — idempotent demo data |
| [`Makefile`](Makefile) | `make dev` boots local infra + seeds |

## Local development ($0)

```bash
make dev          # boots Postgres/Redis/MinIO + the nginx gateway (:8080), and seeds a demo user + 3 resorts
```

Then run each service from its own repo (`snow-resorts-auth-service`, `-user-service`, `-resort-service`,
`-location`, `-activity`) with the `local` Spring profile:

```bash
cd ../snow-resorts-auth-service && ./mvnw spring-boot:run
```

Demo credentials: `demo@snow-resorts.com` / `Password123!`.

### API gateway + unified Swagger UI (:8080)

`make dev` also starts an **nginx gateway on :8080** (mirrors the prod ALB path routing) and a
**unified Swagger UI**. The host services run on 8081-8085; the gateway proxies the
`/snow-resort-service/v1/...` paths to them.

- **One Swagger URL for the whole platform:** http://localhost:8080/swagger/ — use the
  dropdown (top-right) to switch between **auth, user, resort, location, activity**.
- Each dropdown entry loads that service's live springdoc spec, proxied same-origin through
  the gateway at `/api-docs/<service>` (→ the service's `/v3/api-docs`), so there is no CORS.
- "Try it out" calls go back through the gateway (`http://localhost:8080/snow-resort-service/v1/...`),
  so the services must be running for requests to succeed (viewing the contracts works regardless).

## AWS environments

```bash
make tf-staging-plan   # cost-optimized beta
make tf-prod-plan      # full architecture
```

See [`terraform/README.md`](terraform/README.md) for backend setup and the per-environment
cost breakdown. `terraform apply` is run via [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) or manually.
