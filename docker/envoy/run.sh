#!/usr/bin/env sh
# Build the local envoy image and run it on the shared "netlite" Docker network.
set -eu

docker network inspect netlite >/dev/null 2>&1 || docker network create netlite
docker build -t envoy:v1 "$(dirname "$0")"
docker run -d --name envoy -p 8080:8080 --network netlite envoy:v1
