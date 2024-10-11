#!/usr/bin/env sh


echo "Build the Docker image..."
docker build -t nginx:v1 .

echo "NGINX"
docker run -d --name nginx -p 81:80 --network netlite nginx:v1

