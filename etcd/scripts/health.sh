#!/usr/bin/env bash
#
etcdctl --cert tls/tls.crt --key tls/tls.key --cacert tls/ca.crt --endpoints="localhost:2379" endpoint health
