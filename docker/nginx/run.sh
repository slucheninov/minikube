#!/usr/bin/env sh
# Build the local nginx image and run it on the shared "netlite" Docker network.
set -eu

docker network inspect netlite >/dev/null 2>&1 || docker network create netlite
docker build -t nginx:v1 "$(dirname "$0")"
docker run -d --name nginx -p 127.0.0.1:81:80 --network netlite nginx:v1
