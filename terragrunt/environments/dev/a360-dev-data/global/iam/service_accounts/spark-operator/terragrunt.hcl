include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${include.root.locals.modules_root_path}/iam/service_accounts"
}

inputs = {
  database_name = include.root.locals.basename
  location_id   = include.root.locals.region
}

