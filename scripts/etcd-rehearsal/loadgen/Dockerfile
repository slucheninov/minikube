# Load generator + etcdctl/etcdutl toolbox for the coredns etcd rehearsal.
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /loadgen .

FROM gcr.io/etcd-development/etcd:v3.7.2 AS etcd

FROM alpine:3.22
RUN apk add --no-cache curl jq
COPY --from=etcd /usr/local/bin/etcdctl /usr/local/bin/etcdutl /usr/local/bin/
COPY --from=build /loadgen /usr/local/bin/loadgen
USER 65534
ENTRYPOINT ["/usr/local/bin/loadgen"]
