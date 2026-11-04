const { Op } = require("sequelize");
const { getModels } = require("../models");

async function findById(id) {
    const { Product } = await getModels();
    return Product.findOne({ where: { id } });
}

async function findBySku(sku, excludedId) {
    const { Product } = await getModels();
    const where = excludedId === undefined ? { sku } : { sku, id: { [Op.ne]: excludedId } };
    return Product.findOne({ where });
}

async function create(fields) {
    const { Product } = await getModels();
    return Product.create(fields);
}

async function update(id, fields) {
    const { Product } = await getModels();
    return Product.update(fields, { where: { id } });
}

async function remove(id) {
    const { Product } = await getModels();
    return Product.destroy({ where: { id } });
}

module.exports = { findById, findBySku, create, update, remove };
