const path = require("path");
const { Umzug, SequelizeStorage } = require("umzug");
const { createSequelize, resolveCredentials } = require("./database");
const { getSecretJson } = require("../services/secrets");

const SAFE_IDENTIFIER = /^[A-Za-z0-9_]+$/;

// Creates the API's database user with data-only privileges. Idempotent, so it also applies password changes.
async function provisionAppUser(sequelize, databaseName, { username, password }) {
    if (!SAFE_IDENTIFIER.test(username) || !SAFE_IDENTIFIER.test(databaseName)) {
        throw new Error("Database user and database name may only contain letters, digits and underscores.");
    }
    // Sequelize can't bind a name followed by "@", so the validated username is inlined.
    // logging: false keeps the password out of the logs.
    const account = `'${username}'@'%'`;
    const options = { replacements: { password }, logging: false };
    await sequelize.query(`CREATE USER IF NOT EXISTS ${account} IDENTIFIED BY :password`, options);
    await sequelize.query(`ALTER USER ${account} IDENTIFIED BY :password`, options);
    await sequelize.query(`GRANT SELECT, INSERT, UPDATE, DELETE ON \`${databaseName}\`.* TO ${account}`, options);
}

function createUmzug(sequelize) {
    return new Umzug({
        migrations: { glob: ["*.js", { cwd: path.join(__dirname, "../../migrations") }] },
        context: sequelize.getQueryInterface(),
        storage: new SequelizeStorage({ sequelize }),
        logger: console
    });
}

// Runs with the master credentials (SECRET_ID), which the API itself cannot read.
async function runMigrations() {
    const sequelize = createSequelize(await resolveCredentials(process.env.SECRET_ID));
    try {
        const applied = await createUmzug(sequelize).up();
        if (process.env.APP_SECRET_ID) {
            await provisionAppUser(sequelize, process.env.DATABASE, await getSecretJson(process.env.APP_SECRET_ID));
        }
        return applied.map((migration) => migration.name);
    } finally {
        await sequelize.close();
    }
}

module.exports = { runMigrations, provisionAppUser };
