const { S3Client, PutObjectCommand, DeleteObjectCommand } = require("@aws-sdk/client-s3");
const uuid = require("uuid");

const client = () => new S3Client({ region: process.env.REGION });

// A single PutObject is enough: API Gateway caps request payloads at 10 MB.
async function uploadImage(image) {
    const key = `${uuid.v4()}/${image.name}`;
    await client().send(new PutObjectCommand({
        Bucket: process.env.S3_BUCKET,
        Key: key,
        Body: image.data
    }));
    return key;
}

async function deleteImage(key) {
    await client().send(new DeleteObjectCommand({ Bucket: process.env.S3_BUCKET, Key: key }));
}

module.exports = { uploadImage, deleteImage };
