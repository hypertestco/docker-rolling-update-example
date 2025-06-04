# Basic Rolling Update Demo with Docker & Nginx (No Swarm/Kubernetes)

This project demonstrates a manual rolling update of a simple Node.js application using only core Docker features and an Nginx reverse proxy. It avoids orchestrators like Docker Swarm or Kubernetes to showcase the underlying mechanics.

**Goal:**
To illustrate how a new version of an application can be deployed alongside an old version, with traffic gradually shifting, and then the old version being removed, all managed through Docker networking and Nginx's DNS-based load balancing.

## Components

1.  **Node.js Application (`app/`)**:
    *   A simple HTTP server written in Node.js (`server.js`).
    *   Exposes two endpoints:
        *   `GET /`: Returns "Hello from App Version: [APP_VERSION]".
        *   `GET /health`: Returns `{ "status": "OK", "version": "APP_VERSION", ... }`.
    *   Simulates a configurable startup delay (e.g., service takes time to boot).
    *   The `APP_VERSION` and `STARTUP_DELAY_SECONDS` are passed as build arguments to the Docker image.
2.  **Application Docker Image (`app/Dockerfile`)**:
    *   Builds the Node.js application into a container image.
    *   Tagged as `my-app:v1` and `my-app:v2` during the demo.
3.  **Nginx Reverse Proxy (`nginx/`)**:
    *   Uses the official `nginx:latest` image.
    *   Custom configuration (`nginx/nginx.conf`) to:
        *   Listen on a host port (e.g., 3333).
        *   Proxy requests to an upstream named `app-service`.
        *   Use Docker's internal DNS resolver (`127.0.0.11`) to dynamically discover backend instances associated with the `app-service` network alias. The `resolver ... valid=Xs;` directive controls how often Nginx re-resolves this DNS name.
4.  **Docker Network**:
    *   A custom bridge network (e.g., `rolling-update-net`) is created to allow containers to communicate by name and alias.
5.  **Scenario Script (`run_scenario.sh`)**:
    *   A bash script that automates the Docker commands to execute the rolling update step-by-step.

## Prerequisites

*   Docker installed and running.
*   A terminal or command prompt.
*   Basic understanding of Docker concepts (images, containers, networks, build arguments).
*   `curl` command-line tool (for testing HTTP endpoints).
*   `bash` shell (for running the `run_scenario.sh` script).

## File Structure

```
rolling-update-demo/
├── app/
│   ├── Dockerfile        # Dockerfile for the Node.js app
│   ├── package.json      # Node.js project dependencies
│   └── server.js         # Node.js HTTP server code
├── nginx/
│   └── nginx.conf        # Nginx reverse proxy configuration
├── run_scenario.sh       # Script to automate the demo
└── README.md             # This file
```

## Setup

1.  **Clone the repository or create the files:**
    Ensure you have all the files (`app/Dockerfile`, `app/package.json`, `app/server.js`, `nginx/nginx.conf`, `run_scenario.sh`) in the structure shown above.

2.  **Make the script executable:**
    Open your terminal in the `rolling-update-demo` directory and run:
    ```bash
    chmod +x run_scenario.sh
    ```

## Running the Demonstration

Execute the script from the `rolling-update-demo` directory:

```bash
./run_scenario.sh
```

The script will guide you through the following phases, pausing for you to observe and press **Enter** to continue:

**Phase 0: Preparation & Nginx Startup**
*   Cleans up any previous demo containers/networks.
*   Creates a Docker network named `rolling-update-net`.
*   Starts the Nginx reverse proxy container (`nginx_proxy`).
    *   At this point, Nginx will be running, but requests to it (e.g., `http://localhost:3333/`) will likely result in a `502 Bad Gateway` or `503 Service Unavailable` because no application backends are running yet under the `app-service` alias.

**Phase 1: Deploy App Version 1 (`my-app:1.0.0`)**
*   Builds the first version of the application image (`my-app:1.0.0`) with a configured startup delay (e.g., 10 seconds).
*   Starts a container (`app_v1`) from this image.
    *   This container is connected to the `rolling-update-net` and given the network alias `app-service`.
*   The script waits for `app_v1` to log that its server is listening and then confirms its health via a direct health check.
*   After a brief pause (for Nginx DNS to update), Nginx should start successfully proxying requests to `app_v1`. You can test this by curling `http://localhost:3333/` and `http://localhost:3333/health`.

**Phase 2: Deploy App Version 2 (`my-app:2.0.0`) - Rolling Update**
*   Builds the second version of the application image (`my-app:2.0.0`) with a different startup delay (e.g., 30 seconds).
*   Starts a container (`app_v2`) from this image.
    *   Initially, `app_v2` is connected to `rolling-update-net` but *without* the `app-service` alias.
*   The script waits for `app_v2` to become fully healthy (log check + direct health check).
*   Once `app_v2` is confirmed healthy:
    1.  `app_v2` is temporarily disconnected from `rolling-update-net`.
    2.  `app_v2` is immediately reconnected to `rolling-update-net` with the `app-service` alias.
*   Now, both `app_v1` and `app_v2` are associated with the `app-service` alias. Nginx will start load balancing requests between them (round-robin by default due to DNS resolution returning multiple IPs).
    *   You will see responses from both "Version: 1.0.0" and "Version: 2.0.0" when curling the Nginx endpoint multiple times.

**Phase 3: Complete Rollout (Remove Old Version)**
*   The old application container (`app_v1`) is stopped and removed.
*   After Nginx's DNS cache updates (or it detects `app_v1` is down), all traffic for `app-service` will be directed exclusively to `app_v2`.
    *   Curling the Nginx endpoint will now consistently show "Version: 2.0.0".

**Phase 4: Cleanup**
*   Stops and removes the remaining containers (`app_v2`, `nginx_proxy`).
*   Removes the Docker network (`rolling-update-net`).
*   (Optionally, you can manually remove the built Docker images: `docker rmi my-app:v1 my-app:v2`)

## Key Concepts Demonstrated

*   **Docker Networking:** Using custom bridge networks and network aliases for service discovery.
*   **Nginx as a Reverse Proxy:** Basic proxy configuration.
*   **DNS-based Load Balancing (via Docker):** Nginx's `resolver` directive pointing to Docker's internal DNS (127.0.0.11) allows it to discover multiple instances behind a single service name (network alias).
*   **Manual Rolling Update Steps:**
    1.  Deploy new version alongside old.
    2.  Add new version to the load balancer pool (once healthy).
    3.  Remove old version from the load balancer pool.
*   **Application Health Checks:** The Node.js app has a `/health` endpoint, which the script uses to confirm an instance is ready before adding it to the pool (simulating a more robust deployment).

## Customization

*   **Startup Delays & Versions:** Modify `APP_V1_STARTUP_DELAY`, `APP_V2_STARTUP_DELAY`, `APP_V1_VERSION`, `APP_V2_VERSION` at the top of `run_scenario.sh`.
*   **Nginx Port:** Change `NGINX_HOST_PORT` in `run_scenario.sh`.
*   **Nginx DNS Cache:** The `valid=Xs` in `nginx/nginx.conf` (`resolver 127.0.0.11 valid=5s;`) controls how often Nginx re-queries DNS. A lower value (e.g., `1s`) makes changes visible faster in the demo but increases DNS query load in a real system.
