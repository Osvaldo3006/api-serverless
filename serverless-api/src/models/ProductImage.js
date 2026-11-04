const { DataTypes } = require("sequelize");

module.exports = (sequelize) => sequelize.define("images", {
    image_id: {
        type: DataTypes.INTEGER,
        autoIncrement: true,
        primaryKey: true
    },
    product_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
        references: {
            model: "products",
            key: "id"
        }
    },
    file_name: {
        type: DataTypes.STRING,
        allowNull: false
    },
    s3_bucket_path: {
        type: DataTypes.STRING,
        allowNull: false
    }
}, {
    createdAt: "date_created",
    updatedAt: false
});
