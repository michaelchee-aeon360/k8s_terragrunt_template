locals {
  relative_path     = path_relative_to_include()
  modules_root_path = "${get_repo_root()}//terragrunt/modules"
  information_list  = split("/", local.relative_path)
  env               = local.information_list[0]
  project_id        = local.information_list[1]
  raw_region        = local.information_list[2]
  basename          = basename(local.relative_path)
  region            = local.raw_region == "global" ? "asia-southeast1" : local.raw_region
}

remote_state {
  backend = "gcs"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket   = "${local.env}-${local.project_id}-tfstate"
    prefix   = "${local.relative_path}/terraform.tfstate"
    project  = local.project_id
    location = local.region
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "google" {
  project     = "${local.project_id}"
  region      = "${local.region}"
}
EOF
}

generate "version" {
  path      = "version.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  required_version = "~> 1.14.0"
}
EOF
}