# Securing formae with Basic Authentication on Kubernetes

formae exposes an HTTP API for managing infrastructure resources, stacks, and reconciliation. By default, that API is unauthenticated — fine for development, less fine when the agent is managing production infrastructure. The Helm chart now supports basic authentication as a first-class feature, so you can lock down the API without writing any PKL by hand.

## How it works

formae's basic auth plugin sits in front of every API endpoint. Each request must include an `Authorization: Basic ...` header with credentials that match an authorized user. Passwords are stored as bcrypt hashes — the agent never sees plaintext.

The Helm chart handles the plumbing: it creates a Kubernetes Secret for your credentials, injects them as environment variables, generates the correct PKL authentication block, and switches health probes from HTTP to TCP (since the health endpoint also returns 401 when auth is active).

## Enabling basic auth

Three values:

```yaml
formae:
  auth:
    enabled: true
    basic:
      username: admin
      password: "$2y$10$..."  # bcrypt hash
```

Generate the hash:

```bash
htpasswd -bnBC 10 "" yourPassword | tr -d ':'
```

Then install:

```bash
helm install formae . -f examples/formae-basic-auth.yaml \
  --set postgresql.auth.password=changeme \
  --set-string formae.auth.basic.username=admin \
  --set-string formae.auth.basic.password='$2y$10$...'
```

Note the `--set-string` — bcrypt hashes contain `$` characters that Helm's `--set` would try to interpret as value references.

## Using an existing Secret

If you manage credentials externally — through a GitOps workflow, Vault, or Sealed Secrets — point the chart at your existing Kubernetes Secret instead:

```yaml
formae:
  auth:
    enabled: true
    basic:
      existingSecret: my-auth-secret
      usernameKey: username
      passwordKey: password
```

The chart skips creating its own Secret and references yours in the deployment's env vars. The Secret must exist in the same namespace as the release, with keys matching `usernameKey` and `passwordKey`. The password value must be a bcrypt hash.

## What the chart generates

When you set `formae.auth.enabled: true`, the chart does four things:

**1. Creates a Secret** (unless `existingSecret` is set):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: formae-auth
data:
  username: <base64-encoded username>
  password: <base64-encoded bcrypt hash>
```

**2. Injects environment variables** into the formae container:

```yaml
env:
  - name: FORMAE_AUTH_USERNAME
    valueFrom:
      secretKeyRef:
        name: formae-auth
        key: username
  - name: FORMAE_AUTH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: formae-auth
        key: password
```

**3. Adds the auth plugin to the PKL config:**

```pkl
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
```

The `read("env:...")` calls resolve at agent startup, so the bcrypt hash never appears in the ConfigMap — only a reference to the environment variable.

The `Listing<User>` type annotation matters. Without it, PKL creates untyped dynamic objects that serialize as JSON correctly but are silently ignored by formae's Go deserializer. We found this during end-to-end testing: the agent would start without errors, enforce 401 on all requests, but never accept valid credentials. The fix was adding the `<User>` type parameter so PKL produces properly typed objects.

**4. Switches health probes to TCP:**

```yaml
livenessProbe:
  tcpSocket:
    port: http
readinessProbe:
  tcpSocket:
    port: http
```

With auth enabled, `/api/v1/health` returns 401 for unauthenticated requests. Kubernetes interprets any non-2xx response as a probe failure, so the kubelet would kill the pod every few minutes. TCP probes check that the port is accepting connections without making an HTTP request, sidestepping the auth requirement entirely.

## Bringing your own config

If the chart's auth configuration doesn't cover your use case — multiple users, different auth types, or a more complex PKL setup — you can skip the chart-generated config entirely and provide your own `formae.conf.pkl` as a string:

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
          database = "formae"
        }
      }
    }
    plugins {
      authentication {
        type = "basic"
        authorizedUsers = new Listing<User> {
          new {
            username = read("env:ADMIN_USER")
            password = read("env:ADMIN_PASS")
          }
          new {
            username = read("env:CI_USER")
            password = read("env:CI_PASS")
          }
        }
      }
    }
```

When `existingConfig` is set, all other `formae.*` values are ignored — you own the full config. Inject secrets through `extraEnv` with `secretKeyRef`, and override the health probes to TCP since the chart can't detect that your config has auth enabled:

```yaml
extraEnv:
  - name: ADMIN_USER
    valueFrom:
      secretKeyRef:
        name: my-auth-secret
        key: admin-username
  - name: ADMIN_PASS
    valueFrom:
      secretKeyRef:
        name: my-auth-secret
        key: admin-password

livenessProbe:
  httpGet: null
  tcpSocket:
    port: http
  initialDelaySeconds: 15
readinessProbe:
  httpGet: null
  tcpSocket:
    port: http
  initialDelaySeconds: 5
```

The `httpGet: null` is required because Helm deep-merges values — without it, both `httpGet` and `tcpSocket` end up in the probe spec and Kubernetes rejects the manifest.

See [`examples/formae-custom-config.yaml`](https://github.com/platform-engineering-labs/formae-helm/blob/main/examples/formae-custom-config.yaml) for a complete working example.

## Verifying it works

After installing, port-forward and test:

```bash
kubectl port-forward deploy/formae 49684:49684
```

Without credentials:

```bash
curl http://localhost:49684/api/v1/health
# Unauthorized (401)
```

With credentials:

```bash
curl -u admin:yourPassword http://localhost:49684/api/v1/health
# null (200)
```

The chart source and all examples are at [platform-engineering-labs/formae-helm](https://github.com/platform-engineering-labs/formae-helm).
