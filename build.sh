#!/bin/bash

#Fail on any error
set -e

docker buildx build --pull --no-cache --push --platform linux/amd64,linux/arm64,linux/ppc64le,linux/mips64le,linux/arm/v7,linux/arm/v6,linux/s390x -t acspri/quexf:1.21.0 -t acspri/quexf:latest -t adamzammit/quexf:1.21.0 -t adamzammit/quexf:latest .

