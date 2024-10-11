#!/usr/bin/env sh


echo "Build the Docker image..."
docker build -t envoy:v1 .

echo "Assuming Envoy is configured to listen on port 8080, you can now start it in Docker with"
docker run -d --name envoy -p 8080:8080 --network netlite envoy:v1

