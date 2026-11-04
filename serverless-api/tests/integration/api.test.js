// Needs a real MySQL server: set HOST, DB_PORT, DATABASE, DB_USERNAME and DB_PASSWORD (see .env.example).
// DB_USERNAME must be able to create tables and users. S3 is mocked.
require("dotenv").config();
const request = require("supertest");

jest.mock("../../src/services/imageStorage");
const imageStorage = require("../../src/services/imageStorage");
const { runMigrations, provisionAppUser } = require("../../src/config/migrator");
const { getSequelize, createSequelize } = require("../../src/config/database");
const app = require("../../src/app");

const suffix = Date.now();
const username = `jane.${suffix}@example.com`;
const plainPassword = "with,comma:and:colon";
const auth = `Basic ${Buffer.from(`${username}:${plainPassword}`).toString("base64")}`;
const sku = `SKU-${suffix}`;

afterAll(async () => {
    await (await getSequelize()).close();
});

describe("migrations", () => {
    test("are idempotent", async () => {
        await runMigrations();
        expect(await runMigrations()).toEqual([]);
    });

    test("the app user can use the data but cannot change the schema", async () => {
        const admin = createSequelize({ username: process.env.DB_USERNAME, password: process.env.DB_PASSWORD });
        const appCredentials = { username: "webapp_test_user", password: "p'ass\\w,o:rd" };
        await provisionAppUser(admin, process.env.DATABASE, appCredentials);
        await provisionAppUser(admin, process.env.DATABASE, appCredentials);

        const appUser = createSequelize(appCredentials);
        try {
            await expect(appUser.query("SELECT COUNT(*) FROM users")).resolves.toBeDefined();
            await expect(appUser.query("DROP TABLE images")).rejects.toThrow(/denied/i);
            await expect(appUser.query("CREATE TABLE hacked (id INT)")).rejects.toThrow(/denied/i);
            await expect(appUser.query("CREATE USER 'x'@'%' IDENTIFIED BY 'y'")).rejects.toThrow(/denied/i);
        } finally {
            await appUser.close();
            await admin.query("DROP USER 'webapp_test_user'@'%'");
            await admin.close();
        }
    });

    test("provisioning rejects unsafe identifiers", async () => {
        await expect(provisionAppUser({}, "webapp", { username: "x'; DROP", password: "p" })).rejects.toThrow(/letters/);
    });
});

describe("API flow", () => {
    let userId;
    let productId;
    let imageId;

    const productBody = { name: "Chair", description: "Wood", sku, manufacturer: "Acme", quantity: 5 };

    test("creates a user without exposing the password", async () => {
        const res = await request(app).post("/user")
            .send({ username, password: plainPassword, first_name: "Jane", last_name: "Doe" });
        expect(res.status).toBe(201);
        expect(res.body.password).toBeUndefined();
        expect(res.body.account_created).toBeDefined();
        userId = res.body.id;
    });

    test("the UNIQUE index allows only one of several simultaneous sign-ups", async () => {
        const email = `race.${suffix}@example.com`;
        const body = { username: email, password: "secret", first_name: "A", last_name: "B" };
        const results = await Promise.all(Array.from({ length: 5 }, () => request(app).post("/user").send(body)));
        const statuses = results.map((res) => res.status).sort();
        expect(statuses).toEqual([201, 400, 400, 400, 400]);
    });

    test("logs in with a password containing commas and colons", async () => {
        const res = await request(app).get(`/user/${userId}`).set("Authorization", auth);
        expect(res.status).toBe(200);
        expect(res.body.username).toBe(username);
    });

    test("creates, reads and updates a product", async () => {
        const created = await request(app).post("/product").set("Authorization", auth).send(productBody);
        expect(created.status).toBe(201);
        expect(created.body.owner_user_id).toBe(userId);
        productId = created.body.id;

        const patched = await request(app).patch(`/product/${productId}`).set("Authorization", auth).send({ quantity: 7 });
        expect(patched.status).toBe(204);

        const read = await request(app).get(`/product/${productId}`);
        expect(read.body.quantity).toBe(7);
    });

    test("rejects a quantity out of range and a repeated SKU", async () => {
        const range = await request(app).patch(`/product/${productId}`).set("Authorization", auth).send({ quantity: 101 });
        expect(range.status).toBe(400);
        const repeated = await request(app).post("/product").set("Authorization", auth).send(productBody);
        expect(repeated.status).toBe(400);
        expect(repeated.body.Message).toBe("The given SKU is already taken.");
    });

    test("uploads, lists and deletes an image", async () => {
        imageStorage.uploadImage.mockResolvedValue(`${suffix}/a.png`);
        const uploaded = await request(app).post(`/product/${productId}/image`).set("Authorization", auth)
            .attach("image", Buffer.from([0x89, 0x50, 0x4e, 0x47]), { filename: "a.png", contentType: "image/png" });
        expect(uploaded.status).toBe(201);
        imageId = uploaded.body.image_id;

        const listed = await request(app).get(`/product/${productId}/image`).set("Authorization", auth);
        expect(listed.body).toHaveLength(1);

        const deleted = await request(app).delete(`/product/${productId}/image/${imageId}`).set("Authorization", auth);
        expect(deleted.status).toBe(204);
        expect(imageStorage.deleteImage).toHaveBeenCalledWith(`${suffix}/a.png`);
    });

    test("deletes the product along with its images", async () => {
        imageStorage.uploadImage.mockResolvedValue(`${suffix}/b.png`);
        await request(app).post(`/product/${productId}/image`).set("Authorization", auth)
            .attach("image", Buffer.from([0x89]), { filename: "b.png", contentType: "image/png" });

        const deleted = await request(app).delete(`/product/${productId}`).set("Authorization", auth);
        expect(deleted.status).toBe(204);
        expect(imageStorage.deleteImage).toHaveBeenCalledWith(`${suffix}/b.png`);
        expect((await request(app).get(`/product/${productId}`)).status).toBe(404);
    });
});
