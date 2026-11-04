const { Sequelize } = require("sequelize");
const { getSecretJson } = require("../services/secrets");

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

function createSequelize({ username, password }) {
    return new Sequelize(process.env.DATABASE, username, password, {
        host: process.env.HOST,
        port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 3306,
        dialect: "mysql",
        timezone: "-05:00"
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
