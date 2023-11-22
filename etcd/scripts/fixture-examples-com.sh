#!/usr/bin/env bash
#
#
ETCDCTL_API=3 etcdctl  --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" del /skydns/com/example --prefix

etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/x1 '{"ttl":60,"text":"etcd test text"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/x2 '{"host":"10.10.10.1","ttl":60}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/x3 '{"host":"10.10.10.2","ttl":60}'
# ns
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/dns/ns/ns1 '{"host":"10.10.30.1","ttl":60}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/dns/ns/ns2 '{"host":"10.10.30.2","ttl":60}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/dns/ns/ns3 '{"host":"10.10.30.3","ttl":60}'
#

#test instances
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/mongodb-retention/mongodb-retention-1/a '{"host":"10.10.100.1","ttl":60,"priority":10,"port":27017,"owner":"mongodb-retention-1"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/mongodb-retention/mongodb-retention-2/a '{"host":"10.10.100.2","ttl":60,"priority":10,"port":27017,"owner":"mongodb-retention-2"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/mongodb-retention/mongodb-retention-3/a '{"host":"10.10.100.3","ttl":60,"priority":10,"port":27017,"owner":"mongodb-retention-3"}'
# txt owner
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/mongodb-retention/mongodb-retention-1/txt '{"text":"owner/mongodb-retention-1","owner":"mongodb-retention-1"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/mongodb-retention/mongodb-retention-2/txt '{"text":"owner/mongodb-retention-2","owner":"mongodb-retention-2"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/mongodb-retention/mongodb-retention-3/txt '{"text":"owner/mongodb-retention-3","owner":"mongodb-retention-3"}'


#k8s
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/auth/prod-4/auth-5f8d97b7f-4jz27/a '{"host":"10.10.0.1","ttl":60,"priority":10,"port":8080,"owner":"prod-4/auth-5f8d97b7f-4jz27"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/auth/prod-5/auth-5f8d97b7f-5bb5d/a '{"host":"10.10.0.2","ttl":60,"priority":10,"port":8080,"owner":"prod-5/auth-5f8d97b7f-5bb5d"}'
etcdctl --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" put /skydns/com/example/coredns/auth/prod-4/auth-5f8d97b7f-72hfc/a '{"host":"10.10.0.3","ttl":60,"priority":10,"port":8080,"owner":"prod-4/auth-5f8d97b7f-72hfc"}'


#/skydns/com/example/nginx/478eab02 '{"host":"10.103.57.254","ttl":60,"targetstrip":1}'
#/skydns/com/example/nginx/67ad57be  '{"host":"10.100.75.25","text":"\"heritage=external-dns,external-dns/owner=cluster-1,external-dns/resource=service/nginx/nginx\"","ttl":60,"targetstrip":1}'

ETCDCTL_API=3 etcdctl  --cert tls.crt --key tls.key --cacert ca.crt --endpoints="localhost:2379" get /skydns/com/example --prefix

#/