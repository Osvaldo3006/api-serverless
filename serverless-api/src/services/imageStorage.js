const AWS = require("aws-sdk");
const uuid = require("uuid");

const client = () => new AWS.S3({ region: process.env.REGION });

async function uploadImage(image) {
    const result = await client().upload({
        Bucket: process.env.S3_BUCKET,
        Key: `${uuid.v4()}/${image.name}`,
        Body: image.data
    }).promise();
    return result.Key;
}

async function deleteImage(key) {
    await client().deleteObject({ Bucket: process.env.S3_BUCKET, Key: key }).promise();
}

module.exports = { uploadImage, deleteImage };
