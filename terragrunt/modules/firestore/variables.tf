variable "database_name" {
  description = "The name of the database"
  type        = string
}

variable "location_id" {
  description = "The location of the database"
  type        = string
}

variable "type" {
  description = "The database type"
  type        = string
  default     = "FIRESTORE_NATIVE"
}