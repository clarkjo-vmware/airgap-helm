#!/bin/bash

# Set your private registry URL here
PRIVATE_REGISTRY="your-private-registry.local"
LOCAL_REPO="your-local-repo"

# Check if Helm and Docker are installed
if ! command -v helm &> /dev/null || ! command -v docker &> /dev/null; then
    echo "Helm and Docker are required but not installed. Please install them first."
    exit 1
fi

# Check if the chart path is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_helm_chart>"
    exit 1
fi

# Extract the chart name from the chart path
CHART_NAME=$(basename "$1")

# Directory for storing images (this won't be used directly, we will save to a single tarball)
OUTPUT_DIR="./image_bundles"
mkdir -p "$OUTPUT_DIR"

# Define the tarball name for the chart
FINAL_TARBALL="$OUTPUT_DIR/${CHART_NAME}-images.tar"

# Remove any existing tarball from previous runs
if [ -f "$FINAL_TARBALL" ]; then
    rm "$FINAL_TARBALL"
fi

# Function to extract and retag images from a chart
process_chart() {
    local chart_dir=$1
    local chart_name=$(basename "$chart_dir")

    # Skip library charts (Helm errors on library charts since they aren't installable)
    if helm show chart "$chart_dir" | grep -q "library: true"; then
        echo "Skipping library chart: $chart_name"
        return
    fi

    # Render the chart into Kubernetes manifests using values.yaml (if present)
    echo "Rendering chart: $chart_name"
    rendered_output=$(helm template "$chart_dir" -f "$chart_dir/values.yaml")

    # Save the rendered output with chart name and -template.yaml suffix
    echo "$rendered_output" > "$OUTPUT_DIR/${chart_name}-template.yaml"
    echo "Rendered output saved to: $OUTPUT_DIR/${chart_name}-template.yaml"

    # Improved regex to extract image URLs, now using awk for compatibility
    echo "$rendered_output" | awk '/image:/ {print $2}' | sed 's/"//g' | while read image; do
        # Ensure we get a valid image reference
        if [ -z "$image" ]; then
            continue
        fi

        echo "Found image: $image"

        # Debug: Check if the image is valid
        # Updated regex to be more permissive with valid image formats
        if [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._/-]+$ ]]; then
            echo "Skipping invalid image reference: $image"
            continue
        fi

        # Pull the image
        echo "Attempting to pull image: $image"
        docker pull "$image"

        # Construct new tag for the private registry
        image_name=$(echo "$image" | cut -d '/' -f 2-)
        new_image="$PRIVATE_REGISTRY/$LOCAL_REPO/$image_name"

        # Retag the image for local private registry
        echo "Retagging image: $image as $new_image"
        docker tag "$image" "$new_image"

        # Save the image to the consolidated tarball
        echo "Saving image $new_image to tarball"
        if ! docker save "$new_image" | cat >> "$FINAL_TARBALL"; then
            echo "Error saving image $new_image"
        else
            echo "Image $new_image added to tarball."
        fi
    done
}

# Process the main chart
process_chart "$1"

# Find subcharts and process them
subcharts_dir="$1/charts"
if [ -d "$subcharts_dir" ]; then
    for subchart in "$subcharts_dir"/*; do
        if [ -d "$subchart" ]; then
            process_chart "$subchart"
        fi
    done
fi

echo "All images pulled, retagged, and saved to $FINAL_TARBALL"
