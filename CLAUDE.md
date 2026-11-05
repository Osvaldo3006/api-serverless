# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Portfolio project: a Node.js/Express REST API on AWS Lambda, API Gateway, Aurora MySQL and S3, provisioned with Terraform. It started as an import of `NotHarshhaa/DevOps-Projects` (DevOps-Project-22) and is being reworked.

Nothing is deployed and no AWS account is connected yet. Code runs locally and Terraform has only been validated and applied against mocked providers. These have never been exercised on real AWS: binary image delivery through API Gateway, the Aurora master user creating the API database user, and the availability of the Aurora engine version in a given region.

## Working agreements

- Everything in the repo (code, comments, docs, commit messages, branch names, PR descriptions) is in English.
- `main` is the default branch. Each change gets its own branch off `main` and uses Conventional Commits.
- Show the user the commit message and wait for approval before committing.

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

Copy `.env.example` to `.env` for local runs. Integration tests connect with `DB_USERNAME`, which must be able to create users and grant privileges, because they exercise `provisionAppUser`. S3 is mocked in those tests.

Terraform (1.11 or later) runs from `terraform/environments/<env>` or `terraform/bootstrap`:

```sh
terraform fmt -recursive                  # from terraform/
terraform init -backend=false             # enough for validate, no AWS needed
terraform validate
```

A real deployment needs `terraform init -backend-config="bucket=<name>" -backend-config="region=<region>"` and a `terraform.tfvars`.

Terraform reads the Lambda package from `serverless-api/dist/function.zip`, so `plan` and `apply` fail until it is built. Build it with PowerShell 7, not Windows PowerShell 5.1, whose zip files use backslashes in paths that Lambda can't load:

```powershell
npm ci --omit=dev
New-Item -ItemType Directory -Force dist
Compress-Archive -Force -Path index.js, migrate.js, package.json, src, migrations, node_modules -DestinationPath dist/function.zip
```

`npm ci --omit=dev` removes Jest from `node_modules`, so run `npm install` again before testing. A new top-level file or directory the code needs at runtime must also be added to the `Compress-Archive` list.

## Application architecture

Request flow: `index.js` (`serverless-http` when `ENVIRONMENT=lambda`, otherwise `app.listen`) → `src/app.js` → `src/routes/index.js` → middleware → controllers → repositories → Sequelize models.

- **Routes are the source of truth for the API.** They are mounted at `/`, with no `/v1` prefix. The endpoint list in `README.md` is out of date. Each path also needs a `router.all(..., methodNotAllowed)` entry so unsupported verbs return 405 instead of 404.
- **Auth is HTTP Basic, checked on every request** against the bcrypt hash in the database. `authenticate` sets `req.user`. Product and image routes then use `requireOwnedProduct(message)` for ownership checks.
- **Errors:** wrap async handlers in `asyncHandler` so failures reach `middleware/errorHandler.js`, which maps them to the `{ Status, Message }` response shape.
- **Lazy, cached database access:** `getSequelize()` and `getModels()` cache a promise across warm Lambda invocations and clear it on failure so the next request retries. Importing `src/app` doesn't touch the database, which is why unit tests can run by mocking repositories with `jest.mock`.
- **Credentials:** `resolveCredentials` uses Secrets Manager when `SECRET_ID` is set, otherwise `DB_USERNAME`/`DB_PASSWORD`.

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

- `terraform/bootstrap` creates the S3 state bucket once per account, and its own state stays local.
- `terraform/environments/{dev,prod}` are separate roots with separate state, and their `main.tf` files differ only in the environment name. Apply wiring changes to both.
- Module dependency order, which avoids cycles: `network` → `database` and `storage` → `iam` → `lambda` → `api-gateway`.
- `lambda` has an explicit `depends_on` on `network`, `database` and `iam`, because the migrator runs during apply and needs the database instance, the Secrets Manager endpoint and the IAM attachments to exist first.
- The database password uses an ephemeral `random_password` and write-only `secret_string_wo`, so it stays out of state. That means it only changes when `app_db_password_version` is increased.

## Planned work

Done one at a time, each only after the user approves it. Remove items from this list as they merge.

- **D1:** remove the unused `aws_iam_policy.aurora` and replace the custom ENI policy with `AWSLambdaVPCAccessExecutionRole`.
- **D2:** set `skip_final_snapshot` and `force_destroy` per environment.
- **D3:** add environment `outputs.tf`, `terraform.tfvars.example`, and a log group with retention.
- **D4:** migrate to AWS SDK v3, replace `body-parser` with `express.json()`, and use a UTC timezone in Sequelize.
- **D5:** rewrite `README.md`, including the outdated endpoint list, while keeping credit to the original author.
- **D6:** add GitHub Actions workflows using OIDC. `.github/workflows` is currently empty.
- **Open question:** whether to add `UNIQUE` on `sku`, which has the same race condition as `username`.
