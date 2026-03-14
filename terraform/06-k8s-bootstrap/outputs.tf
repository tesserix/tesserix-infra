output "argocd_server" {
  description = "ArgoCD server service name"
  value       = "argocd-server.argocd.svc.cluster.local"
}


output "istio_ingress_ip" {
  description = "Istio ingress gateway ClusterIP (internal only, Cloudflare Tunnel connects to this)"
  value       = "istio-ingressgateway.istio-system.svc.cluster.local"
}
