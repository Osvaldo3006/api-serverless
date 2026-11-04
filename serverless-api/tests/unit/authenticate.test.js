const request = require("supertest");
const bcrypt = require("bcryptjs");

jest.mock("../../src/repositories/userRepository");
const userRepository = require("../../src/repositories/userRepository");
const app = require("../../src/app");

const basic = (credentials) => `Basic ${Buffer.from(credentials).toString("base64")}`;

function mockUser(plainPassword) {
    userRepository.findByUsername.mockResolvedValue({
        id: 1,
        username: "jane@example.com",
        password: bcrypt.hashSync(plainPassword, 4),
        get: () => ({ id: 1, username: "jane@example.com", password: "hash", first_name: "Jane" })
    });
}

describe("authenticate", () => {
    beforeEach(() => jest.resetAllMocks());

    test.each(["with,comma", "with:colon", "a,b:c,d"])("accepts the password %s", async (plainPassword) => {
        mockUser(plainPassword);
        const res = await request(app).get("/user/1").set("Authorization", basic(`jane@example.com:${plainPassword}`));
        expect(res.status).toBe(200);
        expect(res.body.password).toBeUndefined();
    });

    test("rejects a wrong password", async () => {
        mockUser("correct");
        const res = await request(app).get("/user/1").set("Authorization", basic("jane@example.com:wrong"));
        expect(res.status).toBe(401);
        expect(res.body.Message).toBe("Username or Password is Incorrect.");
    });

    test("rejects a missing header", async () => {
        const res = await request(app).get("/user/1");
        expect(res.status).toBe(401);
        expect(res.body.Message).toBe("Please provide an Auth token.");
    });

    test.each([
        ["no colon", basic("jane@example.com")],
        ["no password", basic("jane@example.com:")],
        ["no username", basic(":secret")],
        ["another scheme", "Bearer abc"]
    ])("rejects a malformed header without crashing: %s", async (_name, header) => {
        const res = await request(app).get("/user/1").set("Authorization", header);
        expect(res.status).toBe(401);
        expect(res.body.Message).toBe("Username or Password is Invalid.");
        expect(userRepository.findByUsername).not.toHaveBeenCalled();
    });

    test("forbids reading another user", async () => {
        mockUser("correct");
        const res = await request(app).get("/user/2").set("Authorization", basic("jane@example.com:correct"));
        expect(res.status).toBe(403);
    });
});
