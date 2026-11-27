const express = require("express");
const upload = require("express-fileupload");
const router = require("./routes");
const errorHandler = require("./middleware/errorHandler");

const app = express();

app.use(express.json());
app.use(upload());
// Express 5 leaves req.body undefined when no parser matched the request.
app.use((req, res, next) => {
    req.body ??= {};
    next();
});
app.use("/", router);
app.use(errorHandler);

module.exports = app;
