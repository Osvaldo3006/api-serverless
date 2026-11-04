const bcrypt = require("bcryptjs");

const SALT_ROUNDS = 10;

const hash = (password) => bcrypt.hash(password, SALT_ROUNDS);
const compare = (password, hashed) => bcrypt.compare(password, hashed);

module.exports = { hash, compare };
