# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Portfolio project: a Node.js/Express REST API on AWS Lambda, API Gateway, Aurora MySQL and S3, provisioned with Terraform. It started as an import of `NotHarshhaa/DevOps-Projects` (DevOps-Project-22) and is being reworked.

Nothing is deployed, and for cost reasons nothing will be: no AWS account is connected. Code runs locally and Terraform has only been validated and applied against mocked providers. These have never been exercised on real AWS: binary image delivery through API Gateway, the Aurora master user creating the API database user, and the availability of the Aurora engine version in a given region.

## Working agreements

- Everything in the repo (code, comments, docs, commit messages, branch names, PR descriptions) is in English.
- `main` is the default branch. Each change gets its own branch off `main` and uses Conventional Commits.
- Show the user the commit message and wait for approval before committing.
- Propose before changing anything. Each proposal covers one change: what changes, which files, and a short reason, a few lines at most. Wait for the user's approval before editing files or creating a branch, then do only what was approved. If the work turns out to need something the proposal didn't cover, stop and propose it.

## Commands

Node commands run from `serverless-api/` (Node 24 or later). No linter is configured.

```sh
npm install
npm start                       # local server on port 3000
npm run migrate                 # apply pending migrations
npm test                        # unit tests only
npm run test:integration        # needs a real MySQL server, configured in .env

npx jest tests/unit/authenticate.test.js      # one file
npx jest tests/unit -t "accepts the password" # tests matching a name
```

Copy `.env.example` to `.env` for local runs. Locally, `npm run migrate` only applies migrations: it creates the API database user only when `APP_SECRET_ID` is set, and that variable isn't in `.env.example`. Integration tests connect with `DB_USERNAME`, which must be able to create users and grant privileges, because they exercise `provisionAppUser`. S3 is mocked in those tests.

Terraform (1.11 or later) runs from `terraform/environments/<env>` or `terraform/bootstrap`:

```sh
terraform fmt -recursive                  # from terraform/
terraform init -backend=false             # enough for validate, no AWS needed
terraform validate
```

A real deployment needs `terraform init -backend-config="bucket=<name>" -backend-config="region=<region>"` and a `terraform.tfvars`, copied from the environment's `terraform.tfvars.example`.

Terraform reads the Lambda package from `serverless-api/dist/function.zip`, so `plan` and `apply` fail until it is built. Build it with PowerShell 7, not Windows PowerShell 5.1, whose zip files use backslashes in paths that Lambda can't load:

```powershell
npm ci --omit=dev
New-Item -ItemType Directory -Force dist
Compress-Archive -Force -Path index.js, migrate.js, package.json, src, migrations, certs, node_modules -DestinationPath dist/function.zip
```

`npm ci --omit=dev` removes Jest from `node_modules`, so run `npm install` again before testing. A new top-level file or directory the code needs at runtime must also be added to the `Compress-Archive` list.

## Application architecture

Request flow: `index.js` (`serverless-http` when `ENVIRONMENT=lambda`, otherwise `app.listen`) → `src/app.js` → `src/routes/index.js` → middleware → controllers → repositories → Sequelize models.

- **Routes are the source of truth for the API.** They are mounted at `/`, with no `/v1` prefix. The endpoint list in `README.md` is out of date. Each path also needs a `router.all(..., methodNotAllowed)` entry so unsupported verbs return 405 instead of 404. Order matters: real routes come first, then the 405 entries, then the `router.all("*")` 404 catch-all. A route registered after the catch-all is never reached.
- **Auth is HTTP Basic, checked on each request** against the bcrypt hash in the database (no sessions or tokens). Public routes: `GET /healthz`, `POST /user`, `GET /product/:productId`. `authenticate` sets `req.user`. Product and image routes then use `requireOwnedProduct(message)` for ownership checks.
- **Errors:** wrap async handlers in `asyncHandler` so failures reach `middleware/errorHandler.js`, which maps them to the `{ Status, Message }` response shape.
- **Lazy, cached database access:** `getSequelize()` and `getModels()` cache a promise across warm Lambda invocations and clear it on failure so the next request retries. Importing `src/app` doesn't touch the database, which is why unit tests can run by mocking repositories with `jest.mock`.
- **Credentials:** `resolveCredentials` uses Secrets Manager when `SECRET_ID` is set, otherwise `DB_USERNAME`/`DB_PASSWORD`. TLS to the database is opt-in via `DB_TLS=true`, using `certs/rds-global-bundle.pem`. Terraform sets it on both Lambdas because Aurora requires it, and local MySQL usually runs without it.

### Two Lambdas, one artifact

The same zip is deployed twice, with different handlers, roles and credentials:

| Function | Handler | Database credentials | Other access |
| --- | --- | --- | --- |
| API | `index.handler` | App user: `SELECT`, `INSERT`, `UPDATE`, `DELETE` only | S3 bucket |
| Migrator | `migrate.handler` | Aurora master user | Reads both secrets |

Consequences:

- Schema changes must be umzug migrations in `migrations/`, because the API user has no DDL privileges. Nothing calls `sequelize.sync()`, so keep models and migrations in step by hand.
- Terraform invokes the migrator during `apply` (`aws_lambda_invocation` in `modules/lambda`), whenever the artifact hash or `app_db_password_version` changes. A failed migration fails the apply.
- `provisionAppUser` (`src/config/migrator.js`) creates the API database user after migrating and is idempotent. Sequelize can't bind a name followed by `@`, so the username is validated and inlined. The password stays bound, with logging off.

## Infrastructure architecture

- `terraform/bootstrap` runs once per account, in the environments' region, and its own state stays local. It creates the S3 state bucket and the account-level CloudWatch role that API Gateway needs for access logs, which dev and prod would overwrite if each managed it.
- `terraform/environments/{dev,prod}` are separate roots with separate state, and their `main.tf` files differ only in the `locals` block: the environment name and the data protection settings. Module defaults are the protected values, `prod` keeps them, and `dev` opts out so it stays destroyable. Apply wiring changes to both.
- Module dependency order, which avoids cycles: `network` → `database` and `storage` → `iam` → `lambda` → `api-gateway`.
- `lambda` has an explicit `depends_on` on `network`, `database` and `iam`, because the migrator runs during apply and needs the database instance, the Secrets Manager endpoint and the IAM attachments to exist first.
- The database password uses an ephemeral `random_password` and write-only `secret_string_wo`, so it stays out of state. That means it only changes when `app_db_password_version` is increased.

## Planned work

Done one at a time, in the order listed, each only after the user approves it. Remove items from this list as they merge.

The goal is a portfolio project that shows good security, infrastructure structure and network design without overengineering. Hardening comes first, so CI scanners and the README describe the final state.

- **D8, CD with GitHub Actions and OIDC, written but never run:** there is no AWS account, so it is checked only by `terraform validate`, Checkov and the existing CI.
  - `terraform/bootstrap` creates the GitHub OIDC provider and one deploy role per environment. Each role's trust policy accepts only this repository and its own GitHub environment (`sub` = `repo:<owner>/<repo>:environment:<env>`), so a `dev` run can't assume the `prod` role.
  - A single `deploy.yml`, triggered only by `workflow_dispatch` with an `environment` input (`dev` or `prod`), builds the zip and runs `terraform plan` and `apply` for that environment. The `prod` GitHub environment requires manual approval.
  - No stored AWS keys. The workflow must not print `terraform output` or plans to the logs, since they can expose the account ID and resource ARNs.
- **D9, README rewrite:**
  - State plainly that nothing has been deployed and the CD workflow has never run.
  - Fix the outdated endpoint list and keep credit to the original author.
  - Add the architecture diagram and a short section on security decisions.
  - Explain the throttling limits and the API Lambda's reserved concurrency: both are placeholders, not based on measured traffic. Throttling is global to the stage rather than per client, and reserved concurrency caps Aurora connections but can fail to apply on accounts with a low concurrency quota.
  - List what was left out on purpose as next steps for real production: NAT Gateway, WAF, Cognito, automatic secret rotation, multi-region, VPC Flow Logs and X-Ray.
- **Open question:** whether to add `UNIQUE` on `sku`, which has the same race condition as `username`.
