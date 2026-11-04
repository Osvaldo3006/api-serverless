const request = require("supertest");
const { UniqueConstraintError, ValidationError } = require("sequelize");

jest.mock("../../src/repositories/userRepository");
jest.mock("../../src/repositories/productRepository");
const userRepository = require("../../src/repositories/userRepository");
const productRepository = require("../../src/repositories/productRepository");
const app = require("../../src/app");

const newUser = { username: "jane@example.com", password: "secret", first_name: "Jane", last_name: "Doe" };

describe("error handling", () => {
    beforeEach(() => {
        jest.resetAllMocks();
        jest.spyOn(console, "error").mockImplementation(() => {});
    });
    afterEach(() => jest.restoreAllMocks());

    test("a database failure answers 500 instead of hanging, and hides the details", async () => {
        productRepository.findById.mockRejectedValue(new Error("connect ETIMEDOUT 10.0.0.1"));
        const res = await request(app).get("/product/1");
        expect(res.status).toBe(500);
        expect(res.body).toEqual({ Status: 500, Message: "Internal server error." });
    });

    test("a failure inside authentication also answers 500", async () => {
        userRepository.findByUsername.mockRejectedValue(new Error("db down"));
        const header = `Basic ${Buffer.from("jane@example.com:secret").toString("base64")}`;
        const res = await request(app).get("/user/1").set("Authorization", header);
        expect(res.status).toBe(500);
    });

    test("malformed JSON answers 400", async () => {
        const res = await request(app).post("/user").set("Content-Type", "application/json").send("{bad");
        expect(res.status).toBe(400);
    });

    test("a model validation error answers 400", async () => {
        productRepository.findById.mockRejectedValue(new ValidationError("quantity out of range", []));
        const res = await request(app).get("/product/1");
        expect(res.status).toBe(400);
    });

    test("createUser looks up the username instead of loading every user", async () => {
        userRepository.findByUsername.mockResolvedValue({ id: 1 });
        const res = await request(app).post("/user").send(newUser);
        expect(res.status).toBe(400);
        expect(res.body.Message).toBe("The given Username already exists.");
        expect(userRepository.findByUsername).toHaveBeenCalledWith(newUser.username);
    });

    test("losing a sign-up race against the UNIQUE index answers 400", async () => {
        userRepository.findByUsername.mockResolvedValue(null);
        userRepository.create.mockRejectedValue(new UniqueConstraintError({}));
        const res = await request(app).post("/user").send(newUser);
        expect(res.status).toBe(400);
        expect(res.body.Message).toBe("The given Username already exists.");
    });
});
