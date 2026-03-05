output "github_ci_sa_email" {
  value = google_service_account.github_ci.email
}

output "wif_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_emails" {
  value = { for name, sa in google_service_account.services : name => sa.email }
}
