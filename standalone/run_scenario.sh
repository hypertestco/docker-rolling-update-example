#!/bin/bash

# Exit on any error
set -e

# --- Configuration ---
NETWORK_NAME="rolling-update-net"
NGINX_IMAGE="nginx:latest"
NGINX_CONTAINER_NAME="nginx_proxy"
NGINX_CONFIG_PATH="$(pwd)/nginx/nginx.conf"
NGINX_HOST_PORT="3333"

APP_IMAGE_BASENAME="my-app"
APP_CONTAINER_V1_NAME="app_v1"
APP_CONTAINER_V2_NAME="app_v2"
APP_SERVICE_ALIAS="app-service" 

APP_V1_VERSION="1.0.0"
APP_V1_STARTUP_DELAY="10" 

APP_V2_VERSION="2.0.0"
APP_V2_STARTUP_DELAY="30" 
APP_INTERNAL_PORT="8080" 

# --- Helper Functions ---
wait_for_container_log() {
    local container_name="$1"
    local log_pattern="$2"
    local timeout_seconds="$3"
    echo "Waiting up to $timeout_seconds seconds for '$log_pattern' in $container_name logs..."
    if ! timeout "$timeout_seconds" bash -c \
        "until docker logs \"$container_name\" 2>&1 | grep -q \"$log_pattern\"; do sleep 1; done"; then
        echo "Timeout waiting for '$log_pattern' in $container_name logs."
        docker logs "$container_name"
        exit 1
    fi
    echo "'$log_pattern' found in $container_name logs."
}

wait_for_container_health() {
    local container_name="$1"
    local expected_version="$2"
    local health_check_timeout_seconds="$3"
    echo "Waiting up to $health_check_timeout_seconds seconds for $container_name (v$expected_version) to be healthy..."

    local container_ip=""
    for i in {1..5}; do
        container_ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"${NETWORK_NAME}\").IPAddress}}" "$container_name")
        if [ -n "$container_ip" ]; then
            break
        fi
        echo "Could not get IP for $container_name on network $NETWORK_NAME, retrying in 1s..."
        sleep 1
    done

    if [ -z "$container_ip" ]; then
        echo "ERROR: Could not determine IP address for $container_name on network $NETWORK_NAME."
        docker inspect "$container_name"
        exit 1
    fi

    echo "Polling health of $container_name (IP: $container_ip) for version $expected_version..."
    
    if ! timeout "$health_check_timeout_seconds" bash -c \
        "until curl -s --fail http://${container_ip}:${APP_INTERNAL_PORT}/health | grep -q '\"version\":\"${expected_version}\"'; do \
            echo -n '.'; \
            sleep 2; \
        done"; then
        echo "" 
        echo "Timeout waiting for $container_name (v$expected_version) to become healthy at http://${container_ip}:${APP_INTERNAL_PORT}/health."
        echo "Last health check response:"
        curl -s http://${container_ip}:${APP_INTERNAL_PORT}/health || echo "Health check failed to connect."
        exit 1
    fi
    echo "" 
    echo "$container_name (v$expected_version) is healthy."
}

cleanup() {
    echo "--- Cleaning up ---"
    docker stop "$NGINX_CONTAINER_NAME" "$APP_CONTAINER_V1_NAME" "$APP_CONTAINER_V2_NAME" 2>/dev/null || true
    docker rm "$NGINX_CONTAINER_NAME" "$APP_CONTAINER_V1_NAME" "$APP_CONTAINER_V2_NAME" 2>/dev/null || true
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
    echo "Cleanup complete."
}

trap 'echo "An error occurred. Cleaning up..."; cleanup; exit 1;' ERR
trap 'echo "Script interrupted. Cleaning up..."; cleanup; exit 0;' SIGINT

if [ ! -d "app" ] || [ ! -d "nginx" ]; then
    echo "Error: This script must be run from the 'rolling-update-demo' directory"
    echo "which contains 'app/' and 'nginx/' subdirectories."
    exit 1
fi

echo ">>> Phase 0: Preparation & Nginx Startup <<<"
cleanup
sleep 1 

if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    echo "Creating Docker network: $NETWORK_NAME"
    docker network create "$NETWORK_NAME"
else
    echo "Docker network $NETWORK_NAME already exists (or was just recreated)."
fi

echo "Running Nginx container ($NGINX_CONTAINER_NAME) on port $NGINX_HOST_PORT..."
docker run -d --name "$NGINX_CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    -p "${NGINX_HOST_PORT}:80" \
    -v "$NGINX_CONFIG_PATH":/etc/nginx/nginx.conf:ro \
    "$NGINX_IMAGE"

echo "Nginx is starting. It will initially return errors (e.g., 502) for 'app-service' as no backends are up."
echo "You can test this: curl -I http://localhost:${NGINX_HOST_PORT}/"
sleep 3 # Give Nginx a moment to start fully
echo "--------------------------------------"
echo "Press Enter to proceed to Phase 1 (Deploy App Version 1)..."
read


echo ">>> Phase 1: Deploy App Version 1 <<<"
echo "Building app image v1 (${APP_IMAGE_BASENAME}:${APP_V1_VERSION})..."
docker build -q -t "${APP_IMAGE_BASENAME}:${APP_V1_VERSION}" \
    --build-arg APP_VERSION="${APP_V1_VERSION}" \
    --build-arg STARTUP_DELAY_SECONDS="${APP_V1_STARTUP_DELAY}" \
    ./app

echo "Running app container v1 ($APP_CONTAINER_V1_NAME) with startup delay ${APP_V1_STARTUP_DELAY}s..."
docker run -d --name "$APP_CONTAINER_V1_NAME" \
    --network "$NETWORK_NAME" \
    --network-alias "$APP_SERVICE_ALIAS" \
    "${APP_IMAGE_BASENAME}:${APP_V1_VERSION}"

echo "Waiting for app_v1 to start listening (approx ${APP_V1_STARTUP_DELAY}s)..."
wait_for_container_log "$APP_CONTAINER_V1_NAME" "Server listening on port ${APP_INTERNAL_PORT}" $((APP_V1_STARTUP_DELAY + 15))

echo "Confirming app_v1 is healthy directly..."
wait_for_container_health "$APP_CONTAINER_V1_NAME" "$APP_V1_VERSION" 30

echo "App_v1 is now healthy and aliased as '$APP_SERVICE_ALIAS'."
echo "Waiting a few seconds for Nginx to pick up app_v1 (DNS resolution)..."
sleep 6 # Give Nginx time to resolve DNS (respecting 'valid' in nginx.conf)

echo "Verifying v1 through Nginx (http://localhost:${NGINX_HOST_PORT}/)..."
curl -s http://localhost:${NGINX_HOST_PORT}/
curl -s http://localhost:${NGINX_HOST_PORT}/health
echo ""
echo "--------------------------------------"
echo "Press Enter to proceed to Phase 2 (Deploy App Version 2)..."
read


echo ">>> Phase 2: Deploy App Version 2 (Rolling Update - Add New) <<<"
echo "Building app image v2 (${APP_IMAGE_BASENAME}:${APP_V2_VERSION})..."
docker build -q -t "${APP_IMAGE_BASENAME}:${APP_V2_VERSION}" \
    --build-arg APP_VERSION="${APP_V2_VERSION}" \
    --build-arg STARTUP_DELAY_SECONDS="${APP_V2_STARTUP_DELAY}" \
    ./app

echo "Running app container v2 ($APP_CONTAINER_V2_NAME) with startup delay ${APP_V2_STARTUP_DELAY}s..."
docker run -d --name "$APP_CONTAINER_V2_NAME" \
    --network "$NETWORK_NAME" \
    "${APP_IMAGE_BASENAME}:${APP_V2_VERSION}"

echo "Waiting for app_v2 to start listening (approx ${APP_V2_STARTUP_DELAY}s)..."
wait_for_container_log "$APP_CONTAINER_V2_NAME" "Server listening on port ${APP_INTERNAL_PORT}" $((APP_V2_STARTUP_DELAY + 15))

echo "Confirming app_v2 is healthy directly (BEFORE adding to Nginx '$APP_SERVICE_ALIAS' pool)..."
wait_for_container_health "$APP_CONTAINER_V2_NAME" "$APP_V2_VERSION" $((APP_V2_STARTUP_DELAY + 20))

echo "App_v2 is healthy. Now adding it to Nginx load balancing pool with alias '$APP_SERVICE_ALIAS'..."
echo "  Disconnecting $APP_CONTAINER_V2_NAME from $NETWORK_NAME temporarily..."
docker network disconnect "$NETWORK_NAME" "$APP_CONTAINER_V2_NAME"

echo "  Reconnecting $APP_CONTAINER_V2_NAME to $NETWORK_NAME with alias '$APP_SERVICE_ALIAS'..."
docker network connect --alias "$APP_SERVICE_ALIAS" "$NETWORK_NAME" "$APP_CONTAINER_V2_NAME"

echo "Nginx will now start load balancing between v1 and v2. Test multiple times."
echo "Due to Nginx DNS caching (e.g., valid=5s in nginx.conf), it might take a few seconds to see v2 consistently."
sleep 3 # Give a moment for DNS propagation within Docker and Nginx cache to start picking up v2
for i in {1..12}; do 
    response=$(curl -s -w " | HTTP Status: %{http_code}" http://localhost:${NGINX_HOST_PORT}/)
    echo "$response"
    sleep 0.5
done
echo ""
echo "Check health endpoints (should see both versions):"
for i in {1..8}; do 
    curl -s http://localhost:${NGINX_HOST_PORT}/health
    echo ""
    sleep 1
done
echo "--------------------------------------"
echo "Press Enter to proceed to Phase 3 (Remove Old Version)..."
read


echo ">>> Phase 3: Complete Rollout (Remove Old) <<<"
echo "Stopping and removing app container v1 ($APP_CONTAINER_V1_NAME)..."
docker stop "$APP_CONTAINER_V1_NAME"
docker rm "$APP_CONTAINER_V1_NAME"

echo "Nginx should now send all traffic to v2."
echo "Wait a few seconds for Nginx DNS to update and remove v1 from its active connections."
sleep 6 
echo "Test multiple times (should only see v2):"
for i in {1..10}; do
    curl -s http://localhost:${NGINX_HOST_PORT}/
    sleep 0.5
done
echo ""
echo "Check health endpoint (should only see v2):"
curl -s http://localhost:${NGINX_HOST_PORT}/health
echo ""
echo "--------------------------------------"
echo "Press Enter to proceed to Phase 4 (Cleanup)..."
read

echo ">>> Phase 4: Cleanup <<<"
cleanup

echo "--- Scenario Complete ---"