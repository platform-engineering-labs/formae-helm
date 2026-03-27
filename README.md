# formae-helm

Helm chart for deploying the [formae](https://docs.formae.io) infrastructure-as-code agent on Kubernetes with optional PostgreSQL, OpenTelemetry, and Grafana dashboards.

## Deployment Tiers

| Tier | Components | Example |
|------|-----------|---------|
| **Standalone** | formae agent (SQLite) | `examples/formae-only.yaml` |
| **With database** | formae + PostgreSQL | `examples/formae-db.yaml` |
| **With auth** | formae + PostgreSQL + basic auth | `examples/formae-basic-auth.yaml` |
| **Full observability** | formae + PostgreSQL + OTel + Grafana dashboards | `examples/formae-db-grafana.yaml` |
| **Custom config** | Bring your own `formae.conf.pkl` | `examples/formae-custom-config.yaml` |

## Quick Start

```bash
helm install formae . -f examples/formae-only.yaml
```

With PostgreSQL:

```bash
helm install formae . -f examples/formae-db.yaml \
  --set postgresql.auth.password=changeme
```

Full monitoring stack (requires Prometheus + Grafana already running):

```bash
helm install formae . -f examples/formae-db-grafana.yaml \
  --set postgresql.auth.password=changeme
```

See [`examples/quickstart-monitoring.yaml`](examples/quickstart-monitoring.yaml) for a step-by-step guide to deploying the monitoring stack from scratch.

## Configuration

### Datastore

| Parameter | Description | Default |
|-----------|-------------|---------|
| `formae.datastore.type` | Backend type: `postgres`, `sqlite`, `auroradataapi` | `postgres` |
| `formae.datastore.sqlite.filePath` | SQLite database path | `/data/formae.db` |
| `formae.datastore.postgres.host` | External PostgreSQL host (when `postgresql.enabled=false`) | `""` |
| `formae.datastore.auroraDataAPI.clusterARN` | Aurora cluster ARN | `""` |

### PostgreSQL (in-cluster)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.enabled` | Deploy PostgreSQL alongside formae | `true` |
| `postgresql.image.tag` | PostgreSQL image tag | `15-alpine` |
| `postgresql.auth.username` | Database user | `formae` |
| `postgresql.auth.password` | Database password (set via `--set`) | `""` |
| `postgresql.auth.database` | Database name | `formae` |
| `postgresql.auth.existingSecret` | Use an existing Secret for the password | `""` |
| `postgresql.persistence.enabled` | Enable persistent storage | `true` |
| `postgresql.persistence.size` | PVC size | `8Gi` |

### Authentication

| Parameter | Description | Default |
|-----------|-------------|---------|
| `formae.auth.enabled` | Enable basic authentication for the agent API | `false` |
| `formae.auth.basic.username` | Auth username | `""` |
| `formae.auth.basic.password` | Auth password (bcrypt hash) | `""` |
| `formae.auth.basic.existingSecret` | Use an existing Secret for credentials | `""` |
| `formae.auth.basic.usernameKey` | Key in the existing Secret for username | `username` |
| `formae.auth.basic.passwordKey` | Key in the existing Secret for password | `password` |

Generate a bcrypt hash with:

```bash
htpasswd -bnBC 10 "" yourPassword | tr -d ':'
```

Example with inline credentials:

```bash
helm install formae . -f examples/formae-basic-auth.yaml \
  --set postgresql.auth.password=changeme \
  --set-string formae.auth.basic.username=admin \
  --set-string formae.auth.basic.password='$2y$10$...'
```

Example with an existing Kubernetes Secret:

```yaml
formae:
  auth:
    enabled: true
    basic:
      existingSecret: my-auth-secret
      usernameKey: username
      passwordKey: password
```

### Custom Configuration

Instead of using chart values to build `formae.conf.pkl`, you can provide the entire config as a string via `formae.existingConfig`. When set, all other `formae.*` values (auth, datastore, server, etc.) are ignored.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `formae.existingConfig` | Full `formae.conf.pkl` content as a string | `""` |

Use `read("env:...")` in your PKL to reference secrets, and inject them via `extraEnv`:

```yaml
formae:
  existingConfig: |
    amends "formae:/Config.pkl"
    agent {
      server { port = 49684 }
      datastore {
        datastoreType = "postgres"
        postgres {
          host = "my-db"
          password = read("env:FORMAE_DB_PASSWORD")
        }
      }
    }
    plugins {
      authentication {
        type = "basic"
        authorizedUsers = new Listing<User> {
          new {
            username = read("env:FORMAE_AUTH_USERNAME")
            password = read("env:FORMAE_AUTH_PASSWORD")
          }
        }
      }
    }

extraEnv:
  - name: FORMAE_DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-db-secret
        key: password
  - name: FORMAE_AUTH_USERNAME
    valueFrom:
      secretKeyRef:
        name: my-auth-secret
        key: username
  - name: FORMAE_AUTH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-auth-secret
        key: password
```

See [`examples/formae-custom-config.yaml`](examples/formae-custom-config.yaml) for a complete example.

### Observability

| Parameter | Description | Default |
|-----------|-------------|---------|
| `formae.otel.enabled` | Enable OpenTelemetry instrumentation | `false` |
| `formae.otel.otlp.endpoint` | OTLP receiver endpoint | `localhost:4317` |
| `formae.otel.otlp.protocol` | OTLP protocol (`grpc` or `http`) | `grpc` |
| `formae.otel.prometheus.enabled` | Enable Prometheus metrics export | `false` |
| `otelCollector.enabled` | Deploy OTel Collector as sidecar | `false` |

### Grafana Dashboards

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.dashboards.enabled` | Create dashboard ConfigMaps | `true` |
| `grafana.dashboards.label` | Label for Grafana sidecar discovery | `grafana_dashboard` |
| `grafana.dashboards.labelValue` | Label value | `"1"` |
| `grafana.dashboards.folder` | Grafana folder name | `formae` |

### Resources

Sizing recommendations from the [formae docs](https://docs.formae.io/en/latest/operations/installation-upgrades/#container):

| Managed Resources | Memory | CPU |
|-------------------|--------|-----|
| up to 1,000 | 512Mi | 1 |
| 1,000 - 5,000 | 1Gi | 2 |
| 5,000 - 10,000 | 1.5Gi | 2-4 |
| 10,000 - 20,000 | 2Gi | 4 |

## Examples

| File | Description |
|------|-------------|
| [`formae-only.yaml`](examples/formae-only.yaml) | SQLite, ephemeral storage |
| [`formae-only-persistent.yaml`](examples/formae-only-persistent.yaml) | SQLite with PVC |
| [`formae-db.yaml`](examples/formae-db.yaml) | In-cluster PostgreSQL |
| [`formae-db-grafana.yaml`](examples/formae-db-grafana.yaml) | PostgreSQL + Grafana + OTel |
| [`formae-basic-auth.yaml`](examples/formae-basic-auth.yaml) | Basic authentication |
| [`formae-custom-config.yaml`](examples/formae-custom-config.yaml) | Bring your own `formae.conf.pkl` |
| [`formae-external-db.yaml`](examples/formae-external-db.yaml) | External PostgreSQL |
| [`formae-external-db-grafana.yaml`](examples/formae-external-db-grafana.yaml) | External PostgreSQL + Grafana + OTel |
| [`formae-aurora.yaml`](examples/formae-aurora.yaml) | Aurora Data API |
| [`quickstart-monitoring.yaml`](examples/quickstart-monitoring.yaml) | Full monitoring stack walkthrough |
