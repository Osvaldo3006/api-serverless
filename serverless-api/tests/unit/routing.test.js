const request = require("supertest");
const bcrypt = require("bcryptjs");

jest.mock("../../src/repositories/userRepository");
jest.mock("../../src/repositories/productRepository");
const userRepository = require("../../src/repositories/userRepository");
const productRepository = require("../../src/repositories/productRepository");
const app = require("../../src/app");

const basic = (credentials) => `Basic ${Buffer.from(credentials).toString("base64")}`;

describe("routing", () => {
    beforeEach(() => jest.resetAllMocks());

    test.each(["/unknown", "/product/1/image/2/extra"])("an unknown path %s answers 404", async (path) => {
        const res = await request(app).get(path);
        expect(res.status).toBe(404);
    });

    test("an unsupported verb on a known path answers 405", async () => {
        const res = await request(app).delete("/user");
        expect(res.status).toBe(405);
    });

    test("POST /user without a body answers 400", async () => {
        const res = await request(app).post("/user");
        expect(res.status).toBe(400);
        expect(userRepository.findByUsername).not.toHaveBeenCalled();
    });

    test("PATCH /product/:productId without a body answers 400", async () => {
        userRepository.findByUsername.mockResolvedValue({ id: 1, password: bcrypt.hashSync("secret", 4) });
        const res = await request(app).patch("/product/1").set("Authorization", basic("jane@example.com:secret"));
        expect(res.status).toBe(400);
        expect(productRepository.findById).not.toHaveBeenCalled();
    });
});
