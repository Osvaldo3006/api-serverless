const AWS = require("aws-sdk");

async function getSecretJson(secretId) {
    const client = new AWS.SecretsManager({ region: process.env.REGION });
    const data = await client.getSecretValue({ SecretId: secretId }).promise();
    return JSON.parse(data.SecretString);
}

module.exports = { getSecretJson };
