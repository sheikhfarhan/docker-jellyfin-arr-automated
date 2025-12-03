#!/bin/bash
echo "--- 🐳 Pulling Updates for All Stacks ---"

# Define your stacks
STACKS=(
  "utilities"
  "caddy"
  "jellyfin"
  "vpn-arr-stack"
  "crowdsec"
  "gotify"
)

BASE_DIR="/mnt/pool01/dockerapps"

for stack in "${STACKS[@]}"; do
  if [ -d "$BASE_DIR/$stack" ]; then
    echo "⬇️  Checking $stack..."
    cd "$BASE_DIR/$stack" || continue

    # --- SPECIAL HANDLING FOR CADDY ---
    # Caddy is a custom build (for Cloudflare plugin), so we cannot 'pull' it.
    # We must 'build --pull' to fetch the latest base image and re-compile.
    if [ "$stack" == "caddy" ]; then
        docker compose build --pull
    else
        docker compose pull
    fi
    # ----------------------------------

    echo "✅  $stack updated."
    echo "-----------------------------------"
  else
    echo "⚠️  Folder $stack not found!"
  fi
done

echo "🎉 All images prepared! Run 'start-stacks.sh' or restart specific services to apply."