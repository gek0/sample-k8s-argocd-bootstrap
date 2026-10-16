#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../../../scripts/lib.sh"

section "ArgoCD Service Patch"

info "Patching argocd-server service type to LoadBalancer ..."
kubectl patch service argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
ok "Service type set to LoadBalancer"

info "Assigning MetalLB IP 192.168.104.52 to argocd-server ..."
kubectl patch service argocd-server -n argocd -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.52"}}}'
ok "Load balancer IP assigned"

section "ArgoCD Admin Password"
info "Fetching initial admin password ..."
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

NODE_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
ok "ArgoCD is accessible at http://192.168.104.52"
info "From Mac via port-forward: ./port-forward.sh 80:${NODE_PORT}/TCP  →  http://localhost:8080"
