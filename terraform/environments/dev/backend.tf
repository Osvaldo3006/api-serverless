# The bucket and region are passed to terraform init: see "Setting up Infrastructure" in the README.
terraform {
  backend "s3" {
    key          = "dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
