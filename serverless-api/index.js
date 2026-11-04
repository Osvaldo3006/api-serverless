require("dotenv").config();
const serverless = require("serverless-http");
const app = require("./src/app");

if (process.env.ENVIRONMENT === "lambda") {
    module.exports.handler = serverless(app);
} else {
    app.listen(3000, () => {
        console.log("Server started on port:3000");
    });
}
