const STRING_FIELDS = ["name", "description", "manufacturer"];
const ALLOWED_FIELDS = [...STRING_FIELDS, "sku", "quantity"];

const badRequest = (res, message) => res.status(400).send({ Status: 400, Message: message });
const has = (body, field) => Object.prototype.hasOwnProperty.call(body, field);

// PUT and POST: all five fields are required, and no others.
function validateFullProduct(req, res, next) {
    const body = req.body;
    const isComplete = STRING_FIELDS.every((field) => typeof body[field] === "string")
        && typeof body.sku === "string"
        && typeof body.quantity === "number"
        && Object.keys(body).length === ALLOWED_FIELDS.length;
    if (!isComplete) {
        return badRequest(res, "Request body is not valid.");
    }

    body.sku = body.sku.trim().toUpperCase();
    if (body.sku === "") {
        return badRequest(res, "SKU is not valid.");
    }
    if (!Number.isInteger(body.quantity)) {
        return badRequest(res, "Product quantity should be an Integer between 0 and 100.");
    }
    return next();
}

// PATCH: any subset of the allowed fields.
function validatePartialProduct(req, res, next) {
    const body = req.body;
    if (Object.keys(body).length < 1) {
        return badRequest(res, "Request body is not valid.");
    }
    for (const field of STRING_FIELDS) {
        if (has(body, field) && typeof body[field] !== "string") {
            return badRequest(res, `${field} is Invalid.`);
        }
    }
    if (has(body, "sku")) {
        if (typeof body.sku !== "string" || body.sku.trim() === "") {
            return badRequest(res, "SKU is Invalid.");
        }
        body.sku = body.sku.trim().toUpperCase();
    }
    if (has(body, "quantity") && !Number.isInteger(body.quantity)) {
        return badRequest(res, "Product quantity should be an Integer between 0 and 100.");
    }
    if (Object.keys(body).some((field) => !ALLOWED_FIELDS.includes(field))) {
        return badRequest(res, "Request body consists of unidentified fields.");
    }
    return next();
}

module.exports = { validateFullProduct, validatePartialProduct };
