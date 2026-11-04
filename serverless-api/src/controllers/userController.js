const validator = require("email-validator");
const { UniqueConstraintError } = require("sequelize");
const userRepository = require("../repositories/userRepository");
const password = require("../services/password");

const isString = (value) => typeof value === "string";

function toPublicUser(user) {
    const { password: _omitted, ...publicFields } = user.get({ plain: true });
    return publicFields;
}

const usernameTaken = (res) => res.status(400).send({ Status: 400, Message: "The given Username already exists." });

const getUser = async (req, res) => {
    if (String(req.user.id) !== req.params.userId) {
        return res.status(403).send({ Status: 403, Message: "You do not have access to view this data." });
    }
    return res.send(toPublicUser(req.user));
};

const createUser = async (req, res) => {
    const { username, password: plainPassword, first_name, last_name } = req.body;
    const isValid = [username, plainPassword, first_name, last_name].every(isString) && validator.validate(username);
    if (!isValid) {
        return res.status(400).send({ Status: 400, Message: "Username is not valid or not all the fields given." });
    }

    if (await userRepository.findByUsername(username)) {
        return usernameTaken(res);
    }

    try {
        const user = await userRepository.create({
            username,
            password: await password.hash(plainPassword),
            first_name,
            last_name
        });
        return res.status(201).send(toPublicUser(user));
    } catch (error) {
        // Two simultaneous sign-ups can both pass the lookup above; the UNIQUE index settles it.
        if (error instanceof UniqueConstraintError) {
            return usernameTaken(res);
        }
        throw error;
    }
};

const updateUser = async (req, res) => {
    const { password: plainPassword, first_name, last_name } = req.body;
    const isValid = [plainPassword, first_name, last_name].every(isString) && Object.keys(req.body).length === 3;
    if (!isValid) {
        return res.status(400).send({ Status: 400, Message: "Request body is invalid." });
    }
    if (String(req.user.id) !== req.params.userId) {
        return res.status(403).send({ Status: 403, Message: "You do not have access to update this user." });
    }

    await userRepository.update(req.user.id, {
        password: await password.hash(plainPassword),
        first_name,
        last_name
    });
    return res.sendStatus(204);
};

module.exports = { getUser, createUser, updateUser };
