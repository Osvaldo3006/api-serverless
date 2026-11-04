// Express 4 does not catch rejected promises, so forward them to the error handler.
module.exports = (handler) => (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
