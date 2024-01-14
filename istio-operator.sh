#!/usr/bin/env zsh

# Install istioctl
istioctl operator init --hub docker.io/istio --operatorNamespace istio-operator --istioNamespace istio-system --tag 1.17.3
