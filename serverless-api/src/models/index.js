const { getSequelize } = require("../config/database");
const defineUser = require("./User");
const defineProduct = require("./Product");
const defineProductImage = require("./ProductImage");

let models;

function getModels() {
    if (!models) {
        models = getSequelize().then((sequelize) => ({
            User: defineUser(sequelize),
            Product: defineProduct(sequelize),
            ProductImage: defineProductImage(sequelize)
        })).catch((error) => {
            models = undefined;
            throw error;
        });
    }
    return models;
}

module.exports = { getModels };
