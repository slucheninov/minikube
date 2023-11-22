#!/usr/bin/env bash
#

curl --cert tls/tls.crt --key tls/tls.key --cacert tls/ca.crt https://localhost:2379/metrics
