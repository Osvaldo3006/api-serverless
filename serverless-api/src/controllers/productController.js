const productRepository = require("../repositories/productRepository");
const imageRepository = require("../repositories/imageRepository");
const imageStorage = require("../services/imageStorage");

const skuTaken = (res) => res.status(400).send({ Status: 400, Message: "The given SKU is already taken." });

const getProduct = async (req, res) => {
    const product = await productRepository.findById(req.params.productId);
    if (!product) {
        return res.status(404).send({ Status: 404, Message: "Product with the given Id does not exist." });
    }
    return res.send(product);
};

const createProduct = async (req, res) => {
    if (await productRepository.findBySku(req.body.sku)) {
        return skuTaken(res);
    }
    const product = await productRepository.create({ ...req.body, owner_user_id: req.user.id });
    return res.status(201).send(product);
};

// Shared by PUT and PATCH: the validation middleware on each route decides which fields are allowed.
const updateProduct = async (req, res) => {
    const { sku } = req.body;
    if (sku && await productRepository.findBySku(sku, req.product.id)) {
        return skuTaken(res);
    }
    await productRepository.update(req.product.id, req.body);
    return res.sendStatus(204);
};

const deleteProduct = async (req, res) => {
    const images = await imageRepository.findByProduct(req.product.id);
    for (const image of images) {
        await imageStorage.deleteImage(image.s3_bucket_path);
    }
    await imageRepository.removeByProduct(req.product.id);
    await productRepository.remove(req.product.id);
    return res.sendStatus(204);
};

module.exports = { getProduct, createProduct, updateProduct, deleteProduct };
