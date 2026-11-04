const { getModels } = require("../models");

async function findById(imageId) {
    const { ProductImage } = await getModels();
    return ProductImage.findOne({ where: { image_id: imageId } });
}

async function findByProduct(productId) {
    const { ProductImage } = await getModels();
    return ProductImage.findAll({ where: { product_id: productId } });
}

async function create(productId, fileName, bucketPath) {
    const { ProductImage } = await getModels();
    return ProductImage.create({ product_id: productId, file_name: fileName, s3_bucket_path: bucketPath });
}

async function remove(imageId) {
    const { ProductImage } = await getModels();
    return ProductImage.destroy({ where: { image_id: imageId } });
}

async function removeByProduct(productId) {
    const { ProductImage } = await getModels();
    return ProductImage.destroy({ where: { product_id: productId } });
}

module.exports = { findById, findByProduct, create, remove, removeByProduct };
