provider "aws" {
  region = var.region_1
}

provider "aws" {
  alias  = "r1"
  region = var.region_1
}

provider "aws" {
  alias  = "r2"
  region = var.region_2
}

# Cognito must be in us-east-1 explicitly
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}
