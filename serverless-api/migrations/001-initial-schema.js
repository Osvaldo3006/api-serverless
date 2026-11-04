const { DataTypes } = require("sequelize");

const id = { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true };
const requiredString = { type: DataTypes.STRING, allowNull: false };
const requiredDate = { type: DataTypes.DATE, allowNull: false };

exports.up = async ({ context: queryInterface }) => {
    await queryInterface.createTable("users", {
        id,
        username: requiredString,
        password: requiredString,
        first_name: requiredString,
        last_name: requiredString,
        account_created: requiredDate,
        account_updated: requiredDate
    });
    await queryInterface.addConstraint("users", {
        fields: ["username"],
        type: "unique",
        name: "users_username_unique"
    });

    await queryInterface.createTable("products", {
        id,
        name: requiredString,
        description: requiredString,
        sku: requiredString,
        manufacturer: requiredString,
        quantity: { type: DataTypes.INTEGER, allowNull: false },
        owner_user_id: {
            type: DataTypes.INTEGER,
            allowNull: false,
            references: { model: "users", key: "id" }
        },
        date_added: requiredDate,
        date_last_updated: requiredDate
    });

    await queryInterface.createTable("images", {
        image_id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
        product_id: {
            type: DataTypes.INTEGER,
            allowNull: false,
            references: { model: "products", key: "id" }
        },
        file_name: requiredString,
        s3_bucket_path: requiredString,
        date_created: requiredDate
    });
};

exports.down = async ({ context: queryInterface }) => {
    await queryInterface.dropTable("images");
    await queryInterface.dropTable("products");
    await queryInterface.dropTable("users");
};
