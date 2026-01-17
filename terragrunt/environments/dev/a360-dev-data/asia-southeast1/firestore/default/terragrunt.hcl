include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}//modules/firestore"
}

inputs = {
  account_id   = include.root.locals.basename
  display_name = "Spark Operator Service Account"
  description  = "Service account for Spark Operator test"
}