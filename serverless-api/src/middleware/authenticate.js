const asyncHandler = require("./asyncHandler");
const userRepository = require("../repositories/userRepository");
const password = require("../services/password");

// Per RFC 7617 only the first colon separates the fields, so passwords may contain ":" or ",".
function parseBasicAuth(header) {
    if (!header.startsWith("Basic ")) {
        return null;
    }
    const decoded = Buffer.from(header.slice("Basic ".length), "base64").toString("utf8");
    const separator = decoded.indexOf(":");
    if (separator < 1 || separator === decoded.length - 1) {
        return null;
    }
    return { username: decoded.slice(0, separator), password: decoded.slice(separator + 1) };
}

const reject = (res, message) => res.status(401).send({ Status: 401, Message: message });

module.exports = asyncHandler(async (req, res, next) => {
    const header = req.headers.authorization;
    if (!header) {
        return reject(res, "Please provide an Auth token.");
    }

    const credentials = parseBasicAuth(header);
    if (!credentials) {
        return reject(res, "Username or Password is Invalid.");
    }

    const user = await userRepository.findByUsername(credentials.username);
    if (!user || !(await password.compare(credentials.password, user.password))) {
        return reject(res, "Username or Password is Incorrect.");
    }

    req.user = user;
    return next();
});
