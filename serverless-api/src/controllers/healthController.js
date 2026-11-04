const health = (req, res) => {
    res.status(200).send({ Status: 200, Message: "Server is up and running." });
};

module.exports = { health };
