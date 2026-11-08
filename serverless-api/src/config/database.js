const fs = require("node:fs");
const path = require("node:path");
const { Sequelize } = require("sequelize");
const { getSecretJson } = require("../services/secrets");

const RDS_CA_BUNDLE = path.join(__dirname, "../../certs/rds-global-bundle.pem");

// Reads credentials from Secrets Manager; DB_USERNAME/DB_PASSWORD are for local runs and tests.
async function resolveCredentials(secretId) {
    if (secretId) {
        return getSecretJson(secretId);
    }
    if (process.env.DB_USERNAME && process.env.DB_PASSWORD !== undefined) {
        return { username: process.env.DB_USERNAME, password: process.env.DB_PASSWORD };
    }
    throw new Error("Database credentials not configured: set SECRET_ID or DB_USERNAME/DB_PASSWORD.");
}

// Aurora requires TLS (require_secure_transport). Local MySQL servers usually don't offer it, so it's opt-in.
function tlsOptions() {
    if (process.env.DB_TLS !== "true") {
        return {};
    }
    return { ssl: { ca: fs.readFileSync(RDS_CA_BUNDLE, "utf8"), rejectUnauthorized: true } };
}

function createSequelize({ username, password }) {
    return new Sequelize(process.env.DATABASE, username, password, {
        host: process.env.HOST,
        port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 3306,
        dialect: "mysql",
        dialectOptions: tlsOptions(),
        timezone: "+00:00"
    });
}

let connection;

// The connection is shared across warm invocations. A failed attempt is not cached, so the next request retries.
function getSequelize() {
    if (!connection) {
        connection = (async () => {
            const sequelize = createSequelize(await resolveCredentials(process.env.SECRET_ID));
            await sequelize.authenticate();
            return sequelize;
        })().catch((error) => {
            connection = undefined;
            throw error;
        });
    }
    return connection;
}

module.exports = { getSequelize, createSequelize, resolveCredentials };
