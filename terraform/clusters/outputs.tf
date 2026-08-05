output "argocd_cluster_ids" {
  description = "Argo CD cluster registration IDs, keyed by cluster name"
  value       = { for name, mod in module.cluster : name => mod.argocd_cluster_id }
}

output "kargo_agent_ids" {
  description = "Kargo agent IDs, keyed by cluster name"
  value       = { for name, mod in module.cluster : name => mod.kargo_agent_id }
}

output "kargo_default_shard" {
  description = "Cluster whose Kargo agent is the default shard (null if not set)"
  value       = var.kargo_default_shard
}

output "argocd_hostname" {
  description = "Hostname of the Argo CD instance, for CLI login (argocd login <hostname>)"
  value       = "${data.akp_instance.argocd.id}.cd.akuity.cloud"
}

output "kargo_hostname" {
  description = "Hostname of the Kargo instance, for CLI login (kargo login --admin https://<hostname>)"
  value       = "${data.akp_kargo_instance.kargo.id}.kargo.akuity.cloud"
}
