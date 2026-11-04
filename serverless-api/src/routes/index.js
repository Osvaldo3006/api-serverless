const express = require("express");
const asyncHandler = require("../middleware/asyncHandler");
const authenticate = require("../middleware/authenticate");
const requireOwnedProduct = require("../middleware/requireOwnedProduct");
const { validateFullProduct, validatePartialProduct } = require("../middleware/validateProduct");
const { health } = require("../controllers/healthController");
const users = require("../controllers/userController");
const products = require("../controllers/productController");
const images = require("../controllers/imageController");

const router = express.Router();

const methodNotAllowed = (req, res) => res.sendStatus(405);

router.get("/healthz", health);

router.post("/user", asyncHandler(users.createUser));
router.get("/user/:userId", authenticate, asyncHandler(users.getUser));
router.put("/user/:userId", authenticate, asyncHandler(users.updateUser));

router.post("/product", authenticate, validateFullProduct, asyncHandler(products.createProduct));
router.get("/product/:productId", asyncHandler(products.getProduct));
router.put("/product/:productId", authenticate, validateFullProduct,
    requireOwnedProduct("User doesn't have access rights to update this product."), asyncHandler(products.updateProduct));
router.patch("/product/:productId", authenticate, validatePartialProduct,
    requireOwnedProduct("User doesn't have access rights to update this product."), asyncHandler(products.updateProduct));
router.delete("/product/:productId", authenticate,
    requireOwnedProduct("User doesn't have access rights to delete this product."), asyncHandler(products.deleteProduct));

router.get("/product/:productId/image", authenticate,
    requireOwnedProduct("User doesn't have access rights to view this product images."), asyncHandler(images.getProductImages));
router.post("/product/:productId/image", authenticate,
    requireOwnedProduct("User doesn't have access to upload an image for this product."), asyncHandler(images.uploadProductImage));
router.get("/product/:productId/image/:imageId", authenticate,
    requireOwnedProduct("User doesn't have access to view this product's images."), asyncHandler(images.getProductImage));
router.delete("/product/:productId/image/:imageId", authenticate,
    requireOwnedProduct("User doesn't have access rights to delete this product's images."), asyncHandler(images.deleteProductImage));

router.all("/healthz", methodNotAllowed);
router.all("/user", methodNotAllowed);
router.all("/user/:userId", methodNotAllowed);
router.all("/product", methodNotAllowed);
router.all("/product/:productId", methodNotAllowed);
router.all("/product/:productId/image", methodNotAllowed);
router.all("/product/:productId/image/:imageId", methodNotAllowed);

router.all("*", (req, res) => res.sendStatus(404));

module.exports = router;
