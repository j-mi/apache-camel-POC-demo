# Apache Camel Weather POC

A small Apache Camel integration built with the **Karavan** VS Code extension and run with **Camel JBang**. It exposes `POST /process`, validates the JSON input, enriches it with a `requestId` and timestamp, calls the open [open-meteo](https://api.open-meteo.com/) weather API, and returns a combined JSON response.

## Architecture (one diagram)

```
client ──POST /process──▶ Camel REST DSL
                          │
                          ├─ validate (name & city not empty) ──▶ 400 on failure
                          ├─ add requestId + timestamp + log
                          ├─ lookup city → (latitude, longitude)
                          ├─ HTTP GET open-meteo /v1/forecast
                          └─ build response JSON ──▶ client
```

Six supported cities are hardcoded (Helsinki, Turku, Tampere, Oulu, Espoo, Vantaa). Unknown cities fall back to Helsinki coordinates with a warning log.

## Files

| Path | Purpose |
|---|---|
| `process.camel.yaml` | The Camel integration (edited in Karavan or by hand). |
| `application.properties` | Camel runtime config (port, route file, health). |
| `Dockerfile` | Container image — Java + JBang + Camel route. |
| `scripts/build-image.sh` | Build the Docker image inside minikube's Docker daemon. |
| `scripts/start.sh` | Bring everything up and port-forward to `localhost:8080`. |
| `scripts/stop.sh` | Stop the port-forward and pause minikube. |
| `scripts/clean.sh` | Nuke the minikube cluster and the build context. |
| `tests/test.http` | REST Client requests for VS Code. |
| `tests/test.sh` | curl smoke tests. |
| `k8s/deployment.yaml` | Kubernetes Deployment with probes + resource limits. |
| `k8s/service.yaml` | NodePort Service exposing port 30080. |

## 0. Install the tools (one-time)

### macOS (Homebrew)

```bash
brew install --cask temurin@21
brew install jbang minikube kubectl
jbang app install camel@apache/camel
code --install-extension camel-karavan.karavan
```

### Ubuntu (22.04 / 24.04)

```bash
# 1. Java 21 (OpenJDK from Ubuntu repos)
sudo apt update
sudo apt install -y openjdk-21-jdk curl ca-certificates

# 2. JBang
curl -Ls https://sh.jbang.dev | bash -s -
echo 'export PATH="$HOME/.jbang/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.jbang/bin:$PATH"
jbang app install camel@apache/camel

# 3. Docker Engine (skip if you already have it)
# Follow https://docs.docker.com/engine/install/ubuntu/ — the short version:
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker "$USER"
# log out / back in (or `newgrp docker`) so the group change takes effect

# 4. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# 5. minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

# 6. Karavan extension for VS Code
code --install-extension camel-karavan.karavan
```

### Verify (both platforms)

```bash
java -version          # should be 21.x
camel --version        # any 4.x
docker --version
kubectl version --client
minikube version
```

## 1. Run locally without Kubernetes (fastest feedback loop)

```bash
camel run process.camel.yaml
```

JBang auto-downloads needed Camel components. It serves on `http://localhost:8080`.

Try it:

```bash
curl -s -X POST http://localhost:8080/process \
  -H "Content-Type: application/json" \
  -d '{"name":"Teemu","city":"Turku"}' | jq
```

Run the smoke tests:

```bash
chmod +x tests/test.sh
./tests/test.sh
```

Useful URLs while running locally:

| URL | What |
|---|---|
| <http://localhost:8080/swagger-ui> | Swagger UI |
| <http://localhost:8080/openapi.json> | OpenAPI 3 spec |
| <http://localhost:8080/health> | Liveness JSON |

## 2. Edit visually with Karavan

In VS Code, open `process.camel.yaml`. The Karavan extension adds a visual designer tab where you can drag/drop processors. Saving in Karavan writes back to the same YAML, and `camel run` reloads automatically.

> Karavan shows duplicate integration entries if it finds more than one `*.camel.yaml` in the workspace. If you ran `camel export` and got a `build/` directory, Karavan will list a second copy of the route from there — delete `build/` and refresh the Karavan view.

## 2b. The `/users` endpoint and `JSONMOCKDB` mode

The app exposes a small "mock DB" so you can demo gated access:

| Endpoint | Method | Purpose |
|---|---|---|
| `/users` | POST | Append `{name, city}` as one line to `data/users.jsonl`. |
| `/users` | GET | Return the current contents as a JSON array. |
| `/process` | POST | Weather lookup (existing behaviour). When `JSONMOCKDB=true`, the (name, city) must already be in the file or you get a `404` with a hint. |

**The `JSONMOCKDB` flag only controls `/process`.** Registrations via `/users` always write to the file regardless; the flag just decides whether `/process` consults that file before fetching weather:

| Flag value | `POST /users` | `GET /users` | `POST /process` |
|---|---|---|---|
| `false` (default) | writes to `data/users.jsonl` | reads `data/users.jsonl` → JSON array | weather lookup, **ignores** the file |
| `true` | writes to `data/users.jsonl` | reads `data/users.jsonl` → JSON array | weather lookup, **but first** checks the file; `404` if (name, city) not registered |

The gate is driven by a single property, `jsonmockdb`. Default value lives in [application.properties](application.properties). Override it in any of these ways (highest precedence first):

| Method | Example | When to use |
|---|---|---|
| OS environment variable | `JSONMOCKDB=true camel run process.camel.yaml` | Quickest local override; same name k8s uses. |
| JVM system property | `camel run -Djsonmockdb=true process.camel.yaml` | When you'd rather pass it as a JVM flag. |
| `application.properties` | Edit `jsonmockdb=false` to `=true` and restart | Persistent default for everyone running the project. |
| Kubernetes env | `kubectl set env deploy/camel-weather-poc JSONMOCKDB=true` (or edit [k8s/deployment.yaml](k8s/deployment.yaml)) | When the app is deployed. |

Camel Main automatically maps the upper-case env var `JSONMOCKDB` onto the lower-case property `jsonmockdb`, so the same value works whether you set it in the properties file, on the JVM, or in the shell/k8s env.

Quick demo:

```bash
# JSONMOCKDB=true side: unregistered user is rejected
curl -i -X POST http://localhost:8080/process \
  -H "Content-Type: application/json" -d '{"name":"Ghost","city":"Helsinki"}'
# HTTP/1.1 404 ... {"error":"User not registered in mock DB", ...}

# Register them
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" -d '{"name":"Ghost","city":"Helsinki"}'

# Same request now succeeds
curl -X POST http://localhost:8080/process \
  -H "Content-Type: application/json" -d '{"name":"Ghost","city":"Helsinki"}'
```

### Data handling

The file lives at `data/users.jsonl`, written by the running Camel app.

- **Locally** (`camel run process.camel.yaml`): `./data/users.jsonl` in your repo directory.
- **In Kubernetes**: `/home/app/data/users.jsonl` inside the pod's container

### `.jsonl`

The file uses **[JSON Lines](https://jsonlines.org/)** — one self-contained JSON object per line:

```
{"name":"Teemu","city":"Turku"}
{"name":"Anna","city":"Helsinki"}
```

We picked it because **the writes are append-only**: each `POST /users` just opens the file in append mode and writes one new line. A normal `users.json` (one big array) would require read-modify-write on every registration, which is awkward to do in Camel YAML without a Java/Groovy bean.

`GET /users` reads the file, joins the lines with commas and wraps in `[...]`, so clients see a normal JSON array — only the *storage* is JSONL.

## 3. Deploy to Kubernetes (minikube)

```bash
./scripts/start.sh        # starts minikube, builds image, applies manifests, port-forwards
```

On first run it will:

1. `minikube start --driver=docker --cpus=2 --memory=4096`
2. Build the `camel-weather-poc:1.0.0` image inside minikube's Docker daemon (uses your local `~/.jbang` and `~/.m2` caches so no slow downloads).
3. `kubectl apply -f k8s/`
4. Wait for the pod to be ready.
5. `kubectl port-forward svc/camel-weather-poc 8080:80` in the foreground.

To stop the run:

```bash
./scripts/stop.sh         # kills port-forward + 'minikube stop' (state is preserved)
```

To start again later:

```bash
./scripts/start.sh        # ~10 s to bring everything back up
```

To wipe the slate:

```bash
./scripts/clean.sh        # deletes the cluster and the temp build context
```

### Inspect the running pod

`kubectl` is the door into the cluster. The most useful commands:

```bash
minikube status                                # is the cluster up?
kubectl get pods -l app=camel-weather-poc      # is the pod healthy?
kubectl logs -f deploy/camel-weather-poc       # tail Camel logs
kubectl describe pod -l app=camel-weather-poc  # why is the pod sad?
```

To get an interactive shell inside the container:

```bash
kubectl exec -it deploy/camel-weather-poc -- bash
```

## Safety basics in place

- **Input validation** — `name` and `city` must both be non-empty; otherwise `400` with a JSON error.
- **No secrets in code** — open-meteo needs no API key.
- **Logging** — request body is logged at INFO, with `requestId` correlation. Don't add real PII here in production.
- **Resource limits** — the k8s Deployment caps CPU at 500m and memory at 512Mi.
- **Liveness + readiness probes** hit `/health` so k8s restarts only when actually broken and only routes traffic when ready.
- **Non-root container** — `runAsNonRoot: true`, drops all Linux capabilities, no privilege escalation.
- **Graceful fallback** — unknown cities log a warning and default to Helsinki rather than crashing.

Production-grade hardening that's *not* done here (out of POC scope): TLS, auth (e.g. JWT), rate limiting, network policies, image signing.

## Testing layers

| Layer | How |
|---|---|
| **Smoke / end-to-end** | `tests/test.sh` and `tests/test.http` — hit the live HTTP endpoint. |
| **Unit (route)** | Add Camel test YAML files (`*-test.yaml`) using `mock:` endpoints; run with `camel test`. Not included in this POC but trivial to add. |
| **In-cluster smoke** | After `./scripts/start.sh`, run `./tests/test.sh` — it points at the port-forwarded service. |
