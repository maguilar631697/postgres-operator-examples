# PostgreSQL Operator Troubleshooting Guide

Complete troubleshooting guide for PostgreSQL Operator v5.8.2 with S3/MinIO backup configuration.

## 📋 Table of Contents
- [Quick Health Check](#quick-health-check)
- [Common Issues](#common-issues)
- [S3/MinIO Backup Issues](#s3minio-backup-issues)
- [Database Connection Issues](#database-connection-issues)
- [Certificate Problems](#certificate-problems)
- [Performance Issues](#performance-issues)
- [Monitoring Commands](#monitoring-commands)
- [Recovery Procedures](#recovery-procedures)

## 🔍 Quick Health Check

### 1. Overall Cluster Status
```bash
# Check cluster status
kubectl get postgrescluster hippo -n postgres-operator

# Expected output:
# NAME    INSTANCES   READY   PRIMARY   REPLICAS   POSTGRES   AGE
# hippo   1           3/3     Ready     2          17         20m
```

### 2. Pod Health Check
```bash
# Check all pods
kubectl get pods -n postgres-operator

# Expected pods:
# hippo-instance1-xxxx-0   4/4     Running   0     15m
# hippo-instance1-xxxx-1   4/4     Running   0     15m  
# hippo-instance1-xxxx-2   4/4     Running   0     15m
# hippo-pgbouncer-xxxx-0   2/2     Running   0     12m
# hippo-pgbouncer-xxxx-1   2/2     Running   0     12m
# hippo-pgbouncer-xxxx-2   2/2     Running   0     12m
# hippo-repo-host-0        2/2     Running   0     15m
```

### 3. Quick Backup Status
```bash
# Check backup repositories
kubectl describe postgrescluster hippo -n postgres-operator | grep -A 20 "pgbackrest"
```

## 🚨 Common Issues

### Issue 1: Cluster Not Starting

**Symptoms:**
- Pods stuck in `Pending` or `CrashLoopBackOff`
- Cluster status shows `Not Ready`

**Diagnosis:**
```bash
# Check pod details
kubectl describe pod hippo-instance1-xxxx-0 -n postgres-operator

# Check events
kubectl get events -n postgres-operator --sort-by='.lastTimestamp'

# Check operator logs
kubectl logs -n postgres-operator deployment/pgo
```

**Common Causes & Solutions:**

1. **Storage Issues:**
   ```bash
   # Check PVC status
   kubectl get pvc -n postgres-operator
   
   # Check storage class
   kubectl get storageclass
   
   # Solution: Ensure storage class exists and has sufficient capacity
   ```

2. **Resource Constraints:**
   ```bash
   # Check node resources
   kubectl top nodes
   kubectl describe nodes
   
   # Solution: Scale cluster or adjust resource requests
   ```

3. **Image Pull Issues:**
   ```bash
   # Check image pull status
   kubectl describe pod hippo-instance1-xxxx-0 -n postgres-operator | grep -A 5 "Events"
   
   # Solution: Check image registry access and credentials
   ```

### Issue 2: Database Connection Failures

**Symptoms:**
- Cannot connect to database
- Connection timeouts
- Authentication failures

**Diagnosis:**
```bash
# Check service endpoints
kubectl get svc -n postgres-operator
kubectl get endpoints -n postgres-operator

# Test internal connectivity
kubectl run test-pod --rm -it --image=postgres:17 -- \
  psql "host=hippo-primary.postgres-operator.svc.cluster.local port=5432 dbname=hippo user=hippo"

# Check external LoadBalancer
kubectl get svc postgres-cluster-loadbalancer -n postgres-operator -o yaml
```

**Solutions:**

1. **LoadBalancer Not Ready:**
   ```bash
   # Check LoadBalancer status
   kubectl describe svc postgres-cluster-loadbalancer -n postgres-operator
   
   # Solution: Ensure LoadBalancer controller is running
   ```

2. **Wrong Credentials:**
   ```bash
   # Get correct credentials
   kubectl get secret hippo-pguser-hippo -n postgres-operator -o jsonpath='{.data.uri}' | base64 -d
   
   # Reset password if needed
   kubectl patch postgrescluster hippo -n postgres-operator --type='merge' \
     -p='{"spec":{"users":[{"name":"hippo","password":"newpassword"}]}}'
   ```

## 💾 S3/MinIO Backup Issues

### Issue 3: S3 Backup Not Working

**Symptoms:**
- Backup jobs failing
- No backups appearing in S3/MinIO
- Error logs mentioning S3 connectivity

**Diagnosis Commands:**
```bash
# Check backup repository status
kubectl get postgrescluster hippo -n postgres-operator -o jsonpath='{.status.pgbackrest.repos}' | jq

# Check repo host logs
kubectl logs -n postgres-operator deployment/hippo-repo-host | grep -i s3

# Check backup jobs
kubectl get jobs -n postgres-operator | grep backup

# Test S3 connectivity from repo host
kubectl exec -n postgres-operator deployment/hippo-repo-host -- \
  pgbackrest check --stanza=db --repo=2
```

**Common S3 Issues & Solutions:**

1. **Wrong S3 Credentials:**
   ```bash
   # Verify secret
   kubectl get secret hippo-s3-backup-secret -n postgres-operator -o yaml
   
   # Test credentials manually
   kubectl run test-s3 --rm -it --image=minio/mc -- \
     mc alias set minio http://10.1.21.8:9000 QiOiO8ayHfHY2vLqIbgj qjAeIi8wh7nsrLw53OzKoelyXidi5ChtfhyNxaec
   
   # Solution: Update secret with correct credentials
   kubectl delete secret hippo-s3-backup-secret -n postgres-operator
   kubectl apply -f s3-backup-secret.yaml
   ```

2. **Bucket Doesn't Exist:**
   ```bash
   # Check bucket exists
   kubectl run test-s3 --rm -it --image=minio/mc -- \
     mc ls minio/postgresql-backups/
   
   # Solution: Create bucket in MinIO
   kubectl run test-s3 --rm -it --image=minio/mc -- \
     mc mb minio/postgresql-backups
   ```

3. **Network Connectivity:**
   ```bash
   # Test network connectivity
   kubectl exec -n postgres-operator deployment/hippo-repo-host -- \
     curl -v http://10.1.21.8:9000
   
   # Check DNS resolution
   kubectl exec -n postgres-operator deployment/hippo-repo-host -- \
     nslookup 10.1.21.8
   
   # Solution: Fix network policies or firewall rules
   ```

4. **MinIO Server Issues:**
   ```bash
   # Check MinIO server status
   curl -v http://10.1.21.8:9000/minio/health/live
   
   # Check MinIO logs
   # (Check your MinIO server logs directly)
   ```

### Issue 4: Backup Schedule Not Running

**Diagnosis:**
```bash
# Check backup schedules
kubectl describe postgrescluster hippo -n postgres-operator | grep -A 10 "schedules"

# Check cron jobs
kubectl get cronjobs -n postgres-operator

# Manual backup trigger test
kubectl annotate postgrescluster hippo -n postgres-operator \
  postgres-operator.crunchydata.com/pgbackrest-backup="$(date)" --overwrite
```

**Solution:**
```bash
# Restart repo host if needed
kubectl rollout restart statefulset/hippo-repo-host -n postgres-operator

# Check operator logs
kubectl logs -n postgres-operator deployment/pgo | grep -i backup
```

## 🔒 Certificate Problems

### Issue 5: TLS Certificate Issues

**Symptoms:**
- SSL/TLS connection errors
- Certificate validation failures

**Diagnosis:**
```bash
# Check certificates
kubectl get certificates -n postgres-operator
kubectl describe certificate hippo-certmanager -n postgres-operator

# Check cert-manager
kubectl get clusterissuer
kubectl describe clusterissuer ca-issuer

# Check certificate secrets
kubectl get secret hippo-tls -n postgres-operator -o yaml
```

**Solutions:**

1. **Certificate Not Ready:**
   ```bash
   # Check cert-manager logs
   kubectl logs -n cert-manager deployment/cert-manager-controller
   
   # Force certificate renewal
   kubectl delete secret hippo-tls -n postgres-operator
   kubectl delete certificate hippo-certmanager -n postgres-operator
   kubectl apply -k .
   ```

2. **ClusterIssuer Issues:**
   ```bash
   # Check issuer status
   kubectl describe clusterissuer ca-issuer
   
   # Recreate issuer if needed
   kubectl delete clusterissuer ca-issuer
   kubectl apply -f ca-issuer.yaml
   ```

## ⚡ Performance Issues

### Issue 6: Slow Database Performance

**Diagnosis:**
```bash
# Check resource usage
kubectl top pods -n postgres-operator

# Check database metrics
kubectl exec -n postgres-operator hippo-instance1-xxxx-0 -c database -- \
  psql -c "SELECT * FROM pg_stat_activity;"

# Check I/O stats
kubectl exec -n postgres-operator hippo-instance1-xxxx-0 -c database -- \
  iostat -x 1 5
```

**Solutions:**

1. **Resource Constraints:**
   ```bash
   # Scale resources
   kubectl patch postgrescluster hippo -n postgres-operator --type='merge' \
     -p='{"spec":{"instances":[{"resources":{"limits":{"cpu":"8","memory":"16Gi"}}}]}}'
   ```

2. **Storage Performance:**
   ```bash
   # Check storage class performance
   kubectl describe storageclass
   
   # Consider faster storage class or increase IOPS
   ```

## 📊 Monitoring Commands

### Real-time Monitoring
```bash
# Watch cluster status
watch 'kubectl get postgrescluster hippo -n postgres-operator'

# Monitor pods
kubectl get pods -n postgres-operator -w

# Follow logs
kubectl logs -n postgres-operator deployment/hippo-repo-host -f

# Monitor backup jobs
kubectl get jobs -n postgres-operator -w

# Check resource usage
watch 'kubectl top pods -n postgres-operator'
```

### Health Check Script
```bash
#!/bin/bash
# Save as health-check.sh

echo "=== PostgreSQL Cluster Health Check ==="
echo "Cluster Status:"
kubectl get postgrescluster hippo -n postgres-operator

echo -e "\nPod Status:"
kubectl get pods -n postgres-operator

echo -e "\nServices:"
kubectl get svc -n postgres-operator

echo -e "\nBackup Repositories:"
kubectl describe postgrescluster hippo -n postgres-operator | grep -A 10 "repos"

echo -e "\nRecent Events:"
kubectl get events -n postgres-operator --sort-by='.lastTimestamp' | tail -10
```

## 🔄 Recovery Procedures

### Disaster Recovery from S3 Backup

1. **List Available Backups:**
   ```bash
   kubectl exec -n postgres-operator deployment/hippo-repo-host -- \
     pgbackrest info --stanza=db --repo=2
   ```

2. **Restore from Backup:**
   ```bash
   # Create restore specification
   kubectl apply -f - <<EOF
   apiVersion: postgres-operator.crunchydata.com/v1beta1
   kind: PostgresCluster
   metadata:
     name: hippo-restore
     namespace: postgres-operator
   spec:
     postgresVersion: 17
     dataSource:
       pgbackrest:
         stanza: "db"
         configuration:
         - secret:
             name: hippo-s3-backup-secret
         global:
           repo1-path: "/hippo-cluster"
         repo:
           name: "repo2"
   EOF
   ```

### Point-in-Time Recovery
```bash
# Restore to specific time
kubectl apply -f - <<EOF
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: hippo-pitr
  namespace: postgres-operator
spec:
  postgresVersion: 17
  dataSource:
    pgbackrest:
      stanza: "db"
      configuration:
      - secret:
          name: hippo-s3-backup-secret
      global:
        repo1-path: "/hippo-cluster"
      repo:
        name: "repo2"
      options:
      - --type=time
      - --target="2024-01-01 12:00:00"
EOF
```

## 🆘 Emergency Procedures

### Complete Cluster Reset
```bash
# WARNING: This deletes all data!
kubectl delete postgrescluster hippo -n postgres-operator
kubectl delete pvc -n postgres-operator -l postgres-operator.crunchydata.com/cluster=hippo
kubectl apply -k .
```

### Operator Reset
```bash
# Restart operator
kubectl rollout restart deployment/pgo -n postgres-operator

# Reinstall operator if needed
helm uninstall postgres-operator -n postgres-operator
helm install postgres-operator ./helm/pgo -n postgres-operator
```

## 📞 Support Resources

- **PostgreSQL Operator Docs**: https://access.crunchydata.com/documentation/postgres-operator/latest/
- **pgBackRest Docs**: https://pgbackrest.org/user-guide.html
- **Community Discord**: https://discord.gg/BnsMEeaPBV
- **GitHub Issues**: https://github.com/CrunchyData/postgres-operator

---

**Remember**: Always test recovery procedures in a non-production environment first!

For additional help, check operator logs: `kubectl logs -n postgres-operator deployment/pgo`