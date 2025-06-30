#!/bin/bash

# PostgreSQL Operator + Cluster Kustomize Deployment Script
# This script deploys PostgreSQL 17 cluster using Kustomize

set -e

NAMESPACE="postgres-operator"
OPERATOR_RELEASE="postgres-operator"
KUSTOMIZE_PATH="."

echo "🚀 Starting PostgreSQL 17 Operator + Cluster deployment with Kustomize..."

# Create namespace if it doesn't exist
echo "📁 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Step 1: Install PostgreSQL Operator from OCI registry
echo "📦 Pulling PostgreSQL Operator chart from OCI registry..."
helm pull oci://registry.developers.crunchydata.com/crunchydata/pgo --untar

echo "⚙️  Installing PostgreSQL Operator using OCI Helm chart..."
helm upgrade --install $OPERATOR_RELEASE ./pgo \
  --namespace $NAMESPACE \
  --create-namespace \
  --values helm/install/values.yaml \
  --wait \
  --timeout=300s

# Wait for operator to be ready
echo "⏳ Waiting for PostgreSQL Operator to be ready..."
kubectl wait --for=condition=Available deployment/postgres-operator --namespace=$NAMESPACE --timeout=300s

# Step 2: Create Certificate Authority first (separate from main kustomize)
echo "🔐 Creating Certificate Authority..."
kubectl apply -f $KUSTOMIZE_PATH/ca-issuer.yaml

# Wait for CA certificate to be ready
echo "⏳ Waiting for CA certificate to be issued..."
kubectl wait --for=condition=Ready certificate/ca-issuer-cert --namespace=cert-manager --timeout=300s

# Step 3: Deploy PostgreSQL 17 cluster using Kustomize
echo "🐘 Deploying PostgreSQL 17 cluster using Kustomize..."
kubectl apply -k $KUSTOMIZE_PATH

# Wait for PostgreSQL cluster to be ready
echo "⏳ Waiting for PostgreSQL cluster to be ready..."
kubectl wait --for=condition=PGClusterInitialized postgrescluster/hippo --namespace=$NAMESPACE --timeout=600s

# Step 4: Wait for LoadBalancers to get external IPs
echo "⏳ Waiting for LoadBalancer services to get external IPs..."
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' service/postgres-cluster-loadbalancer --namespace=$NAMESPACE --timeout=300s || echo "LoadBalancer may still be pending..."
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' service/postgres-cluster-pgbouncer-loadbalancer --namespace=$NAMESPACE --timeout=300s || echo "pgBouncer LoadBalancer may still be pending..."

echo "✅ PostgreSQL 17 deployment completed successfully!"
echo ""
echo "📊 Deployment Status:"
echo "===================="
kubectl get postgrescluster -n $NAMESPACE
echo ""
kubectl get pods -n $NAMESPACE
echo ""
kubectl get services -n $NAMESPACE
echo ""
kubectl get certificates -n $NAMESPACE
echo ""

echo "🔗 Connection Information:"
echo "========================="
echo "📍 Internal Connections:"
echo "  Primary:    hippo-primary.$NAMESPACE.svc.cluster.local:5432"
echo "  pgBouncer:  hippo-pgbouncer.$NAMESPACE.svc.cluster.local:5432"
echo ""
echo "📍 External Connections (LoadBalancer):"
POSTGRES_LB_IP=$(kubectl get service postgres-cluster-loadbalancer -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
PGBOUNCER_LB_IP=$(kubectl get service postgres-cluster-pgbouncer-loadbalancer -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
echo "  Primary:    $POSTGRES_LB_IP:5432"
echo "  pgBouncer:  $PGBOUNCER_LB_IP:5432"
echo ""

echo "🔑 Database Credentials:"
echo "======================="
echo "To get the database passwords, run:"
echo "  # Superuser (rhino):"
echo "  kubectl get secret hippo-pguser-rhino -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "  # Regular user (llama):"
echo "  kubectl get secret hippo-pguser-llama -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
echo ""

echo "📋 Useful Management Commands:"
echo "============================="
echo "  # View cluster status:"
echo "  kubectl describe postgrescluster hippo -n $NAMESPACE"
echo ""
echo "  # View operator logs:"
echo "  kubectl logs -f deployment/postgres-operator -n $NAMESPACE"
echo ""
echo "  # Update cluster configuration:"
echo "  kubectl apply -k $KUSTOMIZE_PATH"
echo ""
echo "  # Trigger manual backup:"
echo "  kubectl annotate postgrescluster hippo -n $NAMESPACE postgres-operator.crunchydata.com/pgbackrest-backup=\"\$(date)\""
echo ""
echo "  # Scale cluster (edit postgres.yaml and reapply):"
echo "  # Edit instances[0].replicas in kustomize/postgres/postgres.yaml"
echo "  # kubectl apply -k $KUSTOMIZE_PATH"
echo ""
echo "🐘 PostgreSQL Version: 17"
echo "📦 Operator Version: 5.8.2"
echo "🎯 Deployment Method: Kustomize" 