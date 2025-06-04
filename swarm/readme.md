# Docker Rolling Update Demo Application

This project demonstrates a Node.js application configured for rolling updates using Docker Swarm. It includes health checks and graceful shutdown mechanisms to ensure zero-downtime deployments.

## Prerequisites

*   Docker installed and running.
*   Docker Swarm initialized (the `deploy.sh` script will attempt to initialize it if not already active).
*   `jq` command-line JSON processor (for the `update-version.sh` script).

## Project Structure

```
.
├── Dockerfile            # Defines the Docker image for the application.
├── docker-compose.yml    # Docker Compose file for deploying the service in Swarm mode.
├── package.json          # Node.js project metadata and dependencies.
├── server.js             # The Express.js application code.
├── deploy.sh             # Script to build and deploy the initial version of the application.
└── update-version.sh     # Script to update the application to a new version with a rolling update.
```

## Getting Started

### 1. Initial Deployment

To build the Docker image and deploy the application for the first time, run the deployment script:

```sh
./deploy.sh
```

This script will:
1.  Check if Docker Swarm mode is active and initialize it if necessary.
2.  Read the current application version from [package.json](package.json).
3.  Build a Docker image tagged with the current version (e.g., `docker-demo-app:1.0.4`).
4.  Deploy the application as a Docker Swarm service named `demo-app` using the [docker-compose.yml](docker-compose.yml) configuration. By default, it deploys 3 replicas.
5.  Monitor the deployment status using `docker service ps demo-app_app`. Press `Ctrl+C` to exit the monitor.

### 2. Accessing the Application

Once deployed, the application will be accessible on port 3000. You can interact with the following endpoints:

*   **`GET /`**: Returns a welcome message and lists available endpoints.
    ```sh
    curl http://localhost:3000/
    ```
*   **`GET /status`**: Returns the application version, container ID, uptime, and current timestamp. This is useful for verifying which version of the application is handling the request.
    ```sh
    curl http://localhost:3000/status
    ```
*   **`GET /health`**: Health check endpoint used by Docker Swarm.
    *   For the first 60 seconds (defined by [`STARTUP_GRACE_PERIOD_MS`](server.js) in [server.js](server.js)), it returns a `503 Service Unavailable` status, indicating the app is initializing.
    *   After the grace period, it returns a `200 OK` status.
    ```sh
    curl http://localhost:3000/health
    ```
*   **`GET /ready`**: Readiness probe endpoint. Returns `200 OK` when the application is ready to receive traffic.
    ```sh
    curl http://localhost:3000/ready
    ```

## Updating the Application (Rolling Update)

To update the application to a new version with a rolling update strategy:

1.  **Modify the application code** as needed (e.g., change a message in [server.js](server.js)).
2.  **Run the update script** with the new version number:

    ```sh
    ./update-version.sh <new-version>
    ```
    For example:
    ```sh
    ./update-version.sh 1.0.5
    ```

This script will:
1.  Update the `version` in [package.json](package.json) to `<new-version>`.
2.  Build a new Docker image tagged with `<new-version>` (e.g., `docker-demo-app:1.0.5`).
3.  Trigger a rolling update of the `demo-app` service using the new image. The [docker-compose.yml](docker-compose.yml) file defines the update strategy:
    *   `parallelism: 1`: Updates one container at a time.
    *   `delay: 10s`: Waits 10 seconds between updating containers.
    *   `order: start-first`: Starts a new container before stopping an old one.
    *   `failure_action: rollback`: Rolls back to the previous version if an update fails.
    *   `monitor: 30s`: How long to monitor a task for health after an update before considering it successful.
4.  Monitor the rolling update process. Press `Ctrl+C` to exit the monitor.

During the rolling update, you can continuously hit the `/status` endpoint to see different container IDs and eventually the new version serving requests.

## How It Works

*   **[server.js](server.js)**: A simple Express server.
    *   It includes a [`APP_START_TIME`](server.js) constant and a [`STARTUP_GRACE_PERIOD_MS`](server.js) (60 seconds).
    *   The `/health` endpoint will fail (return 503) if the app uptime is less than `STARTUP_GRACE_PERIOD_MS`. This prevents Docker Swarm from routing traffic to a new container that hasn't fully initialized.
    *   It implements [`gracefulShutdown`](server.js) for `SIGTERM` and `SIGINT` signals.
*   **[Dockerfile](Dockerfile)**:
    *   Uses a Node.js base image.
    *   Copies `package.json` and installs dependencies.
    *   Copies the application source code.
    *   Exposes port 3000.
    *   Includes a `HEALTHCHECK` instruction that calls the `/health` endpoint.
*   **[docker-compose.yml](docker-compose.yml)**:
    *   Defines a service named `app`.
    *   Specifies the build context (`.`) and image name (uses an environment variable `VERSION` which defaults to `1.0.0`, but is overridden by the scripts).
    *   Configures `deploy` options for replicas and the `update_config` for rolling updates.
    *   Sets up a `healthcheck` that matches the one in the `Dockerfile` but is used by Swarm for managing updates and task health.
*   **[deploy.sh](deploy.sh)**: Script for the initial deployment. It builds the image using the version from [package.json](package.json) and deploys the stack.
*   **[update-version.sh](update-version.sh)**: Script for performing rolling updates. It updates [package.json](package.json), rebuilds the image with the new version tag, and then updates the Docker Swarm service.

This setup ensures that updates are applied gradually, and if a new version fails its health check, Docker Swarm can roll back to the previous stable version, minimizing downtime.