resource "google_firestore_database" "firestore" {
  name        = var.database_name
  location_id = var.location_id
  type        = var.type

}