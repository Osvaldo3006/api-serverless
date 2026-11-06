const { createSequelize } = require("../../src/config/database");

const credentials = { username: "app", password: "secret" };

describe("createSequelize", () => {
    afterEach(() => {
        delete process.env.DB_TLS;
    });

    test("connects without TLS by default", () => {
        const sequelize = createSequelize(credentials);
        expect(sequelize.options.dialectOptions.ssl).toBeUndefined();
    });

    test("verifies the server against the RDS CA bundle when DB_TLS is true", () => {
        process.env.DB_TLS = "true";
        const { ssl } = createSequelize(credentials).options.dialectOptions;
        expect(ssl.rejectUnauthorized).toBe(true);
        expect(ssl.ca).toContain("-----BEGIN CERTIFICATE-----");
    });
});
