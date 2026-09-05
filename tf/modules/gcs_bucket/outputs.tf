output "bucket_name" {
  value       = module.bucket.name
  description = "The created bucket's name"
}

output "bucket_url" {
  value       = module.bucket.url
  description = "The created bucket's gs:// URL"
}

output "self_link" {
  value       = module.bucket.bucket.self_link
  description = "The created bucket's self link"
}
