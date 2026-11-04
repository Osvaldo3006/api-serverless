const bodyParser = require("body-parser");
const express = require("express");
const upload = require("express-fileupload");
const router = require("./routes");
const errorHandler = require("./middleware/errorHandler");

const app = express();

app.use(bodyParser.json());
app.use(upload());
app.use("/", router);
app.use(errorHandler);

module.exports = app;
