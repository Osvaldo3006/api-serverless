const { getModels } = require("../models");

async function findByUsername(username) {
    const { User } = await getModels();
    return User.findOne({ where: { username } });
}

async function create(fields) {
    const { User } = await getModels();
    return User.create(fields);
}

async function update(id, fields) {
    const { User } = await getModels();
    return User.update(fields, { where: { id } });
}

module.exports = { findByUsername, create, update };
