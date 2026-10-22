provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

data "terraform_remote_state" "foundation" {
  backend = "local"

  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ExpiresAt   = var.expires_at
    ManagedBy   = "terraform"
    Stack       = "edge"
  }
}
