#!/bin/bash
set -e

# Check if a version is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <new-version>"
  echo "Example: $0 1.0.1"
  exit 1
fi

NEW_VERSION=$1

# Update version in package.json
echo "Updating version to $NEW_VERSION in package.json"
# Using temporary file to ensure compatibility across different systems
cat package.json | jq ".version = \"$NEW_VERSION\"" > package.json.tmp
mv package.json.tmp package.json

# Build new image with updated version
echo "Building docker-demo-app:$NEW_VERSION"
docker build -t docker-demo-app:$NEW_VERSION .

# Update the service with new image
echo "Deploying version $NEW_VERSION with rolling update strategy..."
VERSION=$NEW_VERSION docker stack deploy -c docker-compose.yml demo-app

# Monitor the rolling update
echo "Monitoring rolling update..."
watch -n 2 'docker service ps demo-app_app --format "{{.Name}}\t{{.Image}}\t{{.CurrentState}}"'

echo
echo "Rolling update completed. The application has been updated to version $NEW_VERSION"
echo "To verify, access the status endpoint: curl http://localhost:3000/status"