const serverless = require("serverless-http");
const bcrypt = require("bcryptjs");

jest.mock("../../src/repositories/userRepository");
jest.mock("../../src/repositories/productRepository");
jest.mock("../../src/repositories/imageRepository");
jest.mock("../../src/services/imageStorage");
const userRepository = require("../../src/repositories/userRepository");
const productRepository = require("../../src/repositories/productRepository");
const imageRepository = require("../../src/repositories/imageRepository");
const imageStorage = require("../../src/services/imageStorage");
const app = require("../../src/app");

// PNG signature followed by every byte value: any text re-encoding would alter it.
const binaryImage = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    Buffer.from(Array.from({ length: 256 }, (_, byte) => byte))
]);

function multipartBody(boundary) {
    return Buffer.concat([
        Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="image"; filename="a.png"\r\nContent-Type: image/png\r\n\r\n`),
        binaryImage,
        Buffer.from(`\r\n--${boundary}--\r\n`)
    ]);
}

test("a base64 multipart event from API Gateway reaches S3 byte for byte", async () => {
    userRepository.findByUsername.mockResolvedValue({ id: 1, password: bcrypt.hashSync("secret", 4) });
    productRepository.findById.mockResolvedValue({ id: 5, owner_user_id: 1 });
    imageStorage.uploadImage.mockResolvedValue("key/a.png");
    imageRepository.create.mockResolvedValue({ image_id: 9 });

    const boundary = "testboundary";
    const response = await serverless(app)({
        httpMethod: "POST",
        path: "/product/5/image",
        headers: {
            "Content-Type": `multipart/form-data; boundary=${boundary}`,
            Authorization: `Basic ${Buffer.from("jane@example.com:secret").toString("base64")}`
        },
        requestContext: {},
        isBase64Encoded: true,
        body: multipartBody(boundary).toString("base64")
    }, {});

    expect(response.statusCode).toBe(201);
    const uploaded = imageStorage.uploadImage.mock.calls[0][0];
    expect(uploaded.mimetype).toBe("image/png");
    expect(Buffer.compare(uploaded.data, binaryImage)).toBe(0);
});
