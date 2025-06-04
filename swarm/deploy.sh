#!/bin/bash
set -e

# Check if we're in swarm mode
if ! docker info | grep -q "Swarm: active"; then
  echo "Initializing Docker Swarm mode..."
  docker swarm init
fi

# Get the current version from package.json
CURRENT_VERSION=$(node -e "console.log(require('./package.json').version);")
echo "Current version is: $CURRENT_VERSION"

# Build the image with the current version tag
echo "Building image docker-demo-app:$CURRENT_VERSION"
docker build -t docker-demo-app:$CURRENT_VERSION .

# Deploy or update the stack
echo "Deploying application..."
VERSION=$CURRENT_VERSION docker stack deploy -c docker-compose.yml demo-app

# Monitor deployment
echo "Monitoring deployment..."
watch -n 2 'docker service ps demo-app_app --format "{{.Name}}\t{{.Image}}\t{{.CurrentState}}"'

# Note: Press Ctrl+C to exit the watch command once deployment is complete