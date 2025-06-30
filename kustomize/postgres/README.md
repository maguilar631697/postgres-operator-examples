# PostgreSQL 17 Cluster Configuration

This directory contains the configuration files for deploying a high-availability PostgreSQL 17 cluster using the Crunchy Data PostgreSQL Operator (PGO) in Kubernetes with Kustomize.

## 📁 File Overview

### Core Configuration Files

| File | Purpose | Description |
|------|---------|-------------|
| `postgres.yaml` | **Main Cluster Config** | Defines the `hippo` PostgreSQL 17 cluster with HA, users, storage, and backup settings |
| `kustomization.yaml` | **Kustomize Config** | Orchestrates the deployment of certificates, cluster, and load balancer services |
| `deploy-postgres-kustomize.sh` | **Deployment Script** | Automated script to deploy operator and PostgreSQL 17 cluster |

### TLS/Security Files

| File | Purpose | Description |
|------|---------|-------------|
| `cert.yaml` | **Primary TLS Certificate** | Certificate for PostgreSQL primary connections (`hippo-tls` secret) |
| `cert-repl.yaml` | **Replication TLS Certificate** | Certificate for PostgreSQL replication (`hippo-repl-tls` secret) |
| `ca-issuer.yaml` | **Certificate Authority** | Self-signed CA issuer for generating PostgreSQL certificates |

### Load Balancer Services

| File | Purpose | Description |
|------|---------|-------------|
| `lb.yaml` | **Primary DB LoadBalancer** | External access to PostgreSQL primary (IP: `10.1.80.155:5432`) |
| `lb-pgbouncer.yaml` | **pgBouncer LoadBalancer** | External access to pgBouncer connection pooler (IP: `10.1.80.156:5432`) |

### Documentation

| File | Purpose | Description |
|------|---------|-------------|
| `decode-cert.md` | **Certificate Guide** | Instructions for decoding and managing TLS certificates |
| `sidecart-container.example.md` | **Sidecar Examples** | Examples for adding sidecar containers to PostgreSQL pods |

## 🐘 PostgreSQL 17 Cluster Specifications

### **Cluster Details**
- **Name**: `hippo`
- **PostgreSQL Version**: **17** (Latest)
- **Namespace**: `postgres-operator`
- **High Availability**: 3 replicas with synchronous replication

### **Storage Configuration**
- **Data Storage**: 10Gi per instance (expandable to 25Gi)
- **WAL Storage**: 10Gi per instance (expandable to 25Gi)
- **Backup Storage**: 1Gi (expandable to 25Gi)
- **Storage Class**: Uses cluster default storage class

### **Database Users**
- **`rhino`**: Superuser with access to `zoo` database
- **`llama`**: Regular user with access to `zoo` database

### **High Availability Features**
- **Synchronous Replication**: Ensures zero data loss
- **Pod Anti-Affinity**: Distributes replicas across different nodes
- **Topology Spread Constraints**: Ensures proper distribution
- **Failsafe Mode**: Automatic failover capabilities

### **Connection Pooling (pgBouncer) - Production Optimized**
- **Replicas**: 3 instances
- **Pool Mode**: Transaction-level pooling for maximum efficiency
- **Connection Limits**: 25 connections per database, 200 total client connections
- **TLS Encryption**: End-to-end TLS with certificate verification
- **Load Balancing**: Round-robin across PostgreSQL instances
- **Anti-Affinity**: Distributed across availability zones
- **Load Balancer**: External access via `10.1.80.156:5432`

### **Backup Configuration**
- **Schedule**: 
  - Full backup: Weekly (Sunday 1 AM)
  - Differential backup: Daily (Monday-Saturday 1 AM)
- **Retention**: 14 days
- **Storage**: Local volume (1Gi, expandable to 25Gi)

### **Monitoring**
- **pgmonitor**: PostgreSQL metrics exporter enabled
- **Prometheus Compatible**: Ready for Prometheus scraping

## 🚀 Quick Deployment

### **Automated Deployment (Recommended)**
```bash
# Navigate to this directory
cd Kubernetes/7_postgress/postgres-operator-examples/kustomize/postgres

# Make the script executable
chmod +x deploy-postgres-kustomize.sh

# Run the complete deployment script
./deploy-postgres-kustomize.sh
```

### **Quick Kustomize Apply (if operator exists)**
```bash
# If PostgreSQL Operator is already installed:
kubectl apply -f ca-issuer.yaml
kubectl wait --for=condition=Ready certificate/ca-issuer-cert -n cert-manager --timeout=300s
kubectl apply -k .
```

## 📋 Manual Deployment Instructions

### Prerequisites
1. **Kubernetes cluster** with kubectl access
2. **Helm 3.x** installed
3. **cert-manager** installed for TLS certificate management
4. **Longhorn** or compatible storage class available
5. **Load balancer** support (Cilium IPAM in this case)

### Step 1: Install PostgreSQL Operator
```bash
# Navigate to the parent directory
cd ../..

# Pull and install the operator
helm pull oci://registry.developers.crunchydata.com/crunchydata/pgo --untar
helm install postgres-operator ./pgo \
  --namespace postgres-operator \
  --create-namespace \
  --values helm/install/values.yaml \
  --wait
```

### Step 2: Create Certificate Authority
```bash
# Navigate back to postgres directory
cd kustomize/postgres

# Create the CA issuer
kubectl apply -f ca-issuer.yaml

# Wait for CA to be ready
kubectl wait --for=condition=Ready certificate/ca-issuer-cert -n cert-manager --timeout=300s
```

### Step 3: Deploy PostgreSQL 17 Cluster
```bash
# Deploy all components using Kustomize
kubectl apply -k .

# Verify deployment
kubectl get postgrescluster -n postgres-operator
kubectl get pods -n postgres-operator
```

## 🔗 Connection Information

### Internal Cluster Access
```bash
# Primary PostgreSQL service
hippo-primary.postgres-operator.svc.cluster.local:5432

# pgBouncer service (recommended for applications)
hippo-pgbouncer.postgres-operator.svc.cluster.local:5432
```

### External Access (via LoadBalancer)
```bash
# Direct PostgreSQL access
10.1.80.155:5432

# pgBouncer access (recommended)
10.1.80.156:5432
```

## 🔑 Database Credentials

### Retrieve User Passwords
```bash
# Get rhino (superuser) password
kubectl get secret hippo-pguser-rhino -n postgres-operator -o jsonpath='{.data.password}' | base64 -d

# Get llama (regular user) password
kubectl get secret hippo-pguser-llama -n postgres-operator -o jsonpath='{.data.password}' | base64 -d
```

### Connection Examples
```bash
# Connect via psql (internal)
psql postgresql://rhino:PASSWORD@hippo-pgbouncer.postgres-operator.svc.cluster.local:5432/zoo

# Connect via psql (external)
psql postgresql://rhino:PASSWORD@10.1.80.156:5432/zoo

# Check PostgreSQL version
psql postgresql://rhino:PASSWORD@10.1.80.156:5432/zoo -c "SELECT version();"
```

## 📊 Management Commands

### Cluster Status
```bash
# Check cluster status
kubectl describe postgrescluster hippo -n postgres-operator

# View all pods
kubectl get pods -n postgres-operator -l postgres-operator.crunchydata.com/cluster=hippo

# Check backup status
kubectl get pod -n postgres-operator -l postgres-operator.crunchydata.com/pgbackrest=hippo

# Check certificates
kubectl get certificates -n postgres-operator
```

### Manual Backup
```bash
# Trigger a manual backup
kubectl annotate postgrescluster hippo -n postgres-operator \
  postgres-operator.crunchydata.com/pgbackrest-backup="$(date)"
```

### Scaling
```bash
# Edit postgres.yaml to change replicas
vim postgres.yaml
# Change instances[0].replicas to desired number

# Apply changes
kubectl apply -k .
```

### Configuration Updates
```bash
# After editing any configuration files
kubectl apply -k .

# Check update status
kubectl get postgrescluster hippo -n postgres-operator -o yaml
```

## 🔧 Troubleshooting

### Certificate Issues
```bash
# Check certificate status
kubectl get certificates -n postgres-operator

# Check ClusterIssuer status
kubectl get clusterissuer ca-issuer

# Describe certificate issues
kubectl describe certificate hippo-certmanager -n postgres-operator
```

### Pod Issues
```bash
# Check pod events
kubectl describe pod <pod-name> -n postgres-operator

# View PostgreSQL logs
kubectl logs -f <postgres-pod-name> -c database -n postgres-operator

# View operator logs
kubectl logs -f deployment/postgres-operator -n postgres-operator
```

### Storage Issues
```bash
# Check PVCs
kubectl get pvc -n postgres-operator

# Check storage class
kubectl get storageclass

# Check Longhorn volumes (if using Longhorn)
kubectl get volumes -n longhorn-system
```

### LoadBalancer Issues
```bash
# Check service status
kubectl get services -n postgres-operator

# Check LoadBalancer events
kubectl describe service postgres-cluster-loadbalancer -n postgres-operator

# Check Cilium IPAM (if using Cilium)
kubectl get ciliumpools
```

## 🔄 PostgreSQL 17 Features

### **New in PostgreSQL 17**
- **Improved Performance**: Enhanced query optimization and execution
- **Better JSON Support**: Advanced JSON processing capabilities
- **Enhanced Security**: Stronger authentication and encryption options
- **Monitoring Improvements**: Better metrics and observability

### **Operator Compatibility**
- **PGO 5.8.2**: Fully supports PostgreSQL 17
- **Automatic Updates**: Operator manages PostgreSQL 17 lifecycle
- **Extension Support**: All major PostgreSQL 17 extensions available

## 📚 Additional Resources

- [PostgreSQL 17 Release Notes](https://www.postgresql.org/docs/17/release-17.html)
- [PostgreSQL Operator Documentation](https://access.crunchydata.com/documentation/postgres-operator/latest/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Kustomize Documentation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

## 🛡️ Security Considerations

- **TLS Encryption**: All connections use TLS encryption with PostgreSQL 17
- **SCRAM-SHA-256**: Strong password authentication (PostgreSQL 17 default)
- **Network Policies**: Consider implementing network policies for additional security
- **RBAC**: Ensure proper RBAC is configured for PostgreSQL operator access
- **Certificate Rotation**: Automatic certificate renewal via cert-manager

## 🔄 Backup and Disaster Recovery

- **pgBackRest Integration**: Native PostgreSQL 17 backup tool
- **Point-in-Time Recovery**: Full PITR capability
- **Cross-Region Backups**: Can be configured for S3/Azure/GCS
- **Automated Scheduling**: Weekly full + daily differential backups
- **Retention Policies**: 14-day retention with configurable cleanup

## 🎯 Production Considerations

### **Resource Requirements (Updated for Optimizations)**
- **CPU**: Minimum 4 cores per PostgreSQL instance (optimized for 4 parallel workers)
- **Memory**: Minimum 8Gi RAM per instance (2GB shared_buffers + 6GB effective_cache_size)
- **Storage**: SSD required for optimal performance (optimized for random_page_cost: 1.1)
- **Network**: Low-latency network for synchronous replication

### **Monitoring Setup**
```bash
# Check PostgreSQL 17 metrics
kubectl port-forward service/hippo-pgbouncer 5432:5432 -n postgres-operator

# Connect and check metrics
psql postgresql://rhino:PASSWORD@localhost:5432/zoo \
  -c "SELECT * FROM pg_stat_activity;"
```

---

**Cluster Name**: hippo  
**PostgreSQL Version**: 17  
**Operator Version**: 5.8.2  
**Deployment Method**: Kustomize  
**Last Updated**: $(date) 