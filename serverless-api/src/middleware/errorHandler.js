const { ValidationError } = require("sequelize");

const isInvalidData = (err) => err instanceof ValidationError || err.original?.code === "ER_DATA_TOO_LONG";

// eslint-disable-next-line no-unused-vars -- Express identifies error handlers by their four arguments.
module.exports = (err, req, res, next) => {
    if (res.headersSent) {
        return next(err);
    }
    if (isInvalidData(err)) {
        return res.status(400).send({ Status: 400, Message: "Request body fields / quantity is invalid." });
    }
    // Client errors raised by middleware, such as malformed JSON.
    if (err.status >= 400 && err.status < 500) {
        return res.status(err.status).send({ Status: err.status, Message: "Request is invalid." });
    }
    console.error("Unhandled error:", err);
    return res.status(500).send({ Status: 500, Message: "Internal server error." });
};
