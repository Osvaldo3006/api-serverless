const imageRepository = require("../repositories/imageRepository");
const imageStorage = require("../services/imageStorage");

const ALLOWED_MIME_TYPES = ["image/jpeg", "image/jpg", "image/png"];

const badRequest = (res, message) => res.status(400).send({ Status: 400, Message: message });

// Returns the image only if it belongs to the product in the URL; otherwise responds with 404.
async function findProductImage(req, res) {
    const image = await imageRepository.findById(req.params.imageId);
    if (!image) {
        res.status(404).send({ Status: 404, Message: "Image with the given Id does not exist." });
        return null;
    }
    if (image.product_id !== req.product.id) {
        res.status(404).send({ Status: 404, Message: "Image not found for the given product." });
        return null;
    }
    return image;
}

const getProductImages = async (req, res) => {
    res.status(200).send(await imageRepository.findByProduct(req.product.id));
};

const getProductImage = async (req, res) => {
    const image = await findProductImage(req, res);
    if (image) {
        res.status(200).send(image);
    }
};

const uploadProductImage = async (req, res) => {
    if (!req.files) {
        return badRequest(res, "Please upload at least one image.");
    }
    const file = req.files.image;
    if (!file) {
        return badRequest(res, "Please upload at least one image by using image key.");
    }
    if (Array.isArray(file)) {
        return badRequest(res, "Only one Image can be uploaded.");
    }
    if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
        return badRequest(res, "Only the file formats JPG, JPEG and PNG are allowed.");
    }

    const key = await imageStorage.uploadImage(file);
    const image = await imageRepository.create(req.product.id, file.name, key);
    return res.status(201).send(image);
};

const deleteProductImage = async (req, res) => {
    const image = await findProductImage(req, res);
    if (image) {
        await imageRepository.remove(image.image_id);
        await imageStorage.deleteImage(image.s3_bucket_path);
        res.sendStatus(204);
    }
};

module.exports = { getProductImages, getProductImage, uploadProductImage, deleteProductImage };
