#!/bin/bash

#Fail on any error
set -e


sysctl -w kernel.randomize_va_space=0
docker buildx build --pull --no-cache --push --platform linux/amd64,linux/arm64,linux/ppc64le,linux/arm/v7,linux/arm/v6,linux/s390x -t acspri/quexf:1.22.0 -t acspri/quexf:latest -t adamzammit/quexf:1.22.0 -t adamzammit/quexf:latest .
sysctl -w kernel.randomize_va_space=2
