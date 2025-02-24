#!/bin/bash

PRIVATE_REGISTRY="your-private-registry.local"
LOCAL_REPO="your-local-repo"
FINAL_TARBALL="./image_bundles/${CHART_NAME}-images.tar"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is required but not installed. Please install it first."
    exit 1
fi

# Check if tarball exists
if [ ! -f "$FINAL_TARBALL" ]; then
    echo "Tarball $FINAL_TARBALL not found. Please ensure the tarball exists."
    exit 1
fi

# Load the tarball into Docker
echo "Loading images from $FINAL_TARBALL into Docker..."
docker load -i "$FINAL_TARBALL"

# Push images to the private registry
docker images --format "{{.Repository}}:{{.Tag}}" | while read image; do
    new_image="$PRIVATE_REGISTRY/$LOCAL_REPO/$image"
    echo "Pushing image $new_image..."
    docker push "$new_image"
done

echo "All images pushed to $PRIVATE_REGISTRY/$LOCAL_REPO."