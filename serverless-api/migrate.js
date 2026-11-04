require("dotenv").config();
const { runMigrations } = require("./src/config/migrator");

// Lambda entry point. Terraform invokes it on each deployment; a failure aborts the apply.
exports.handler = async () => ({ applied: await runMigrations() });

// Local usage: npm run migrate
if (require.main === module) {
    runMigrations()
        .then((applied) => console.log("Migrations applied:", applied))
        .catch((error) => {
            console.error(error);
            process.exitCode = 1;
        });
}
