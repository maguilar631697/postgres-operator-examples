# PostgreSQL Operator (PGO) v5.8.2 - Crunchy Data

Complete deployment guide for PostgreSQL Operator v5.8.2 with PostgreSQL 17.5 support.

## 📋 Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
- [Configuration](#configuration)
- [PostgreSQL Cluster Deployment](#postgresql-cluster-deployment)
- [Management Commands](#management-commands)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Upgrade Guide](#upgrade-guide)

## 🎯 Overview

This repository contains configurations for deploying PostgreSQL clusters using Crunchy Data's PostgreSQL Operator (PGO) v5.8.2. The operator provides enterprise-grade PostgreSQL management with:

- **High Availability**: Multi-replica clusters with automatic failover
- **Backup & Recovery**: Automated backups with pgBackRest
- **Connection Pooling**: pgBouncer integration
- **Monitoring**: Prometheus metrics and alerting
- **TLS Security**: End-to-end encryption
- **PostgreSQL 17.5**: Latest PostgreSQL version support

## 🔧 Prerequisites

- Kubernetes cluster v1.25+
- Helm v3.8+
- kubectl configured
- cert-manager installed (for TLS certificates)
- StorageClass available for persistent volumes

## 🚀 Installation Methods

### Method 1: Helm Installation (Recommended)

#### 1. Install the Operator

```bash
# Create namespace
kubectl create namespace postgres-operator

# Install PGO v5.8.2
helm install postgres-operator ./helm/pgo \
  --namespace postgres-operator \
  --values ./helm/pgo/values.yaml
```

#### 2. Verify Installation

```bash
# Check operator status
kubectl get pods -n postgres-operator
kubectl get deployment -n postgres-operator

# Check operator logs
kubectl logs -n postgres-operator deployment/pgo
```

### Method 2: Kustomize Deployment

```bash
# Deploy PostgreSQL cluster
kubectl apply -k kustomize/postgres/

# Check cluster status
kubectl get postgrescluster -n postgres-operator
```

## ⚙️ Configuration

### Operator Configuration (`helm/pgo/values.yaml`)

| Parameter | Value | Description |
|-----------|--------|-------------|
| `singleNamespace` | `true` | Namespace-scoped operation |
| `debug` | `false` | Debug logging disabled |
| `replicas` | `1` | Single operator instance |
| `AutoGrowVolumes` | `true` | Automatic volume expansion |

### Resource Allocation
```yaml
resources:
  controller:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

### Health Probes
- **Liveness**: `/readyz` on port 8081
- **Readiness**: `/healthz` on port 8081

## 🐘 PostgreSQL Cluster Deployment

### Cluster Specifications

| Component | Version | Configuration |
|-----------|---------|---------------|
| **PostgreSQL** | 17.5-2520 | 3 replicas, synchronous replication |
| **pgBackRest** | 2.54.2-2520 | Weekly full, daily differential backups |
| **pgBouncer** | 1.24-2520 | Transaction pooling, 3 replicas |
| **pgExporter** | 0.17.1-2520 | Prometheus metrics |

### Performance Optimizations

```yaml
postgresql.parameters:
  max_parallel_workers: "4"
  max_worker_processes: "8"
  shared_buffers: "2GB"
  work_mem: "4MB"
  maintenance_work_mem: "256MB"
  effective_cache_size: "6GB"
  random_page_cost: "1.1"        # SSD optimized
  effective_io_concurrency: "200" # SSD optimized
```

### Resource Requirements (Per Instance)
- **CPU**: 4 cores
- **Memory**: 8Gi RAM
- **Storage**: 20Gi (auto-expandable)

## 🔗 Connection Information

### Internal Access
```bash
# Primary connection
kubectl get secret hippo-pguser-hippo -n postgres-operator -o jsonpath='{.data.uri}' | base64 -d

# Service endpoints
hippo-primary.postgres-operator.svc.cluster.local:5432
hippo-replica.postgres-operator.svc.cluster.local:5432
```

### External Access (LoadBalancer)
- **Primary**: `10.1.80.155:5432`
- **pgBouncer**: `10.1.80.156:5432`

### Connection Examples
```bash
# Direct PostgreSQL connection
psql "host=10.1.80.155 port=5432 dbname=hippo user=hippo sslmode=require"

# pgBouncer connection (recommended)
psql "host=10.1.80.156 port=5432 dbname=hippo user=hippo sslmode=require"
```

## 📊 Management Commands

### Cluster Operations
```bash
# Get cluster status
kubectl get postgrescluster hippo -n postgres-operator

# View cluster details
kubectl describe postgrescluster hippo -n postgres-operator

# Check pod status
kubectl get pods -n postgres-operator -l postgres-operator.crunchydata.com/cluster=hippo

# View primary instance
kubectl get pods -n postgres-operator -l postgres-operator.crunchydata.com/role=master
```

### Backup Operations
```bash
# Manual backup
kubectl annotate postgrescluster hippo -n postgres-operator \
  postgres-operator.crunchydata.com/pgbackrest-backup="$(date)"

# List backups
kubectl exec -it deployment/hippo-backup -n postgres-operator -- \
  pgbackrest info --stanza=db
```

### Scaling Operations
```bash
# Scale replicas
kubectl patch postgrescluster hippo -n postgres-operator --type='merge' \
  -p='{"spec":{"instances":[{"replicas":5}]}}'
```

## 📈 Monitoring

### Prometheus Metrics
- Endpoint: `http://hippo-exporter:9187/metrics`
- Namespace: `postgres-operator`
- Service Monitor: Auto-configured

### Key Metrics
- `pg_up`: Database availability
- `pg_stat_database_tup_returned`: Query performance
- `pg_stat_bgwriter_*`: Background writer stats
- `pg_replication_lag`: Replication lag

### Grafana Integration
```yaml
# Add to Grafana datasources
- name: postgresql-hippo
  type: prometheus
  url: http://prometheus:9090
  jsonData:
    httpMethod: POST
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Operator Not Starting
```bash
# Check operator logs
kubectl logs -n postgres-operator deployment/pgo

# Verify RBAC permissions
kubectl auth can-i "*" "*" --as=system:serviceaccount:postgres-operator:pgo
```

#### 2. Cluster Creation Failed
```bash
# Check cluster events
kubectl describe postgrescluster hippo -n postgres-operator

# Check persistent volumes
kubectl get pv,pvc -n postgres-operator
```

#### 3. Certificate Issues
```bash
# Check cert-manager
kubectl get clusterissuer
kubectl describe certificate -n postgres-operator

# Force certificate renewal
kubectl delete secret hippo-cluster-cert -n postgres-operator
```

#### 4. Connection Problems
```bash
# Test internal connectivity
kubectl run test-pod --rm -it --image=postgres:17 -- \
  psql "host=hippo-primary.postgres-operator.svc.cluster.local port=5432 dbname=hippo user=hippo"

# Check service endpoints
kubectl get svc -n postgres-operator
kubectl get endpoints -n postgres-operator
```

## 🔄 Upgrade Guide

### Operator Upgrade
```bash
# Backup current configuration
helm get values postgres-operator -n postgres-operator > backup-values.yaml

# Upgrade to latest version
helm upgrade postgres-operator ./helm/pgo \
  --namespace postgres-operator \
  --values ./helm/pgo/values.yaml

# Verify upgrade
kubectl get deployment pgo -n postgres-operator -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### PostgreSQL Version Upgrade
```bash
# Create PGUpgrade resource
kubectl apply -f - <<EOF
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PGUpgrade
metadata:
  name: hippo-upgrade
  namespace: postgres-operator
spec:
  postgresClusterName: hippo
  fromPostgresVersion: 16
  toPostgresVersion: 17
EOF
```

## 📁 File Structure

```
postgres-operator-examples/
├── helm/
│   └── pgo/
│       ├── Chart.yaml          # Helm chart metadata
│       ├── values.yaml         # Operator configuration
│       ├── templates/          # Kubernetes templates
│       └── crds/              # Custom Resource Definitions
├── kustomize/
│   └── postgres/
│       ├── kustomization.yaml  # Kustomize configuration
│       ├── postgres.yaml       # PostgreSQL cluster spec
│       ├── ca-issuer.yaml      # Certificate authority
│       ├── cert.yaml           # TLS certificates
│       └── lb.yaml            # LoadBalancer services
└── README.md                  # This file
```

## 🔒 Security Features

- **TLS Encryption**: End-to-end encryption for all connections
- **RBAC**: Role-based access control
- **Network Policies**: Pod-to-pod communication security
- **Secret Management**: Kubernetes secrets for credentials
- **Certificate Rotation**: Automatic certificate renewal

## 📚 Additional Resources

- [Crunchy Data Documentation](https://access.crunchydata.com/documentation/postgres-operator/latest/)
- [PostgreSQL 17 Release Notes](https://www.postgresql.org/docs/17/release-17.html)
- [pgBackRest Documentation](https://pgbackrest.org/user-guide.html)
- [Kubernetes PostgreSQL Best Practices](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## 🆘 Support

For issues and support:
1. Check the troubleshooting section above
2. Review operator logs: `kubectl logs -n postgres-operator deployment/pgo`
3. Consult Crunchy Data documentation
4. Open issues in the official repository

---

**Version**: PostgreSQL Operator v5.8.2  
**PostgreSQL**: 17.5  
**Last Updated**: $(date +%Y-%m-%d)  
**Status**: Production Ready ✅

