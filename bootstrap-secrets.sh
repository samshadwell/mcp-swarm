#!/bin/bash
set -euo pipefail

if [ ! -d ".secrets" ]; then
    echo "Error: .secrets directory not found"
    exit 1
fi

for file in .secrets/*; do
    filename=$(basename "$file")
    secret_name="${filename%.*}"
    echo "Creating secret $secret_name..."
    gcloud secrets create "$secret_name" --data-file="$file"
done
