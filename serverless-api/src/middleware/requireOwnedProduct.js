const asyncHandler = require("./asyncHandler");
const productRepository = require("../repositories/productRepository");

module.exports = (forbiddenMessage) => asyncHandler(async (req, res, next) => {
    const product = await productRepository.findById(req.params.productId);
    if (!product) {
        return res.status(404).send({ Status: 404, Message: "Product with the given Id does not exist." });
    }
    if (product.owner_user_id !== req.user.id) {
        return res.status(403).send({ Status: 403, Message: forbiddenMessage });
    }
    req.product = product;
    return next();
});
