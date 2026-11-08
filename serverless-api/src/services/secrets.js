const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");

async function getSecretJson(secretId) {
    const client = new SecretsManagerClient({ region: process.env.REGION });
    const data = await client.send(new GetSecretValueCommand({ SecretId: secretId }));
    return JSON.parse(data.SecretString);
}

module.exports = { getSecretJson };
