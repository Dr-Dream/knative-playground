#!/bin/sh

set -e

for cluster in "$@"
do
  kube_context="k3d-$cluster"
  echo "=== Installing cert-manager === "
  helm --kube-context="$kube_context" upgrade --install \
    --namespace cert-manager \
    --create-namespace \
    --version v1.17.2 \
    --set crds.enabled=true \
    cert-manager jetstack/cert-manager

  echo "=== Installing trust-manager === "

  helm --kube-context="$kube_context" upgrade --install \
    --namespace cert-manager \
    --create-namespace \
    --set app.trust.namespace=cert-manager \
    trust-manager jetstack/trust-manager
done;
