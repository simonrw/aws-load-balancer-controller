# syntax=docker/dockerfile:experimental
ARG BASE_IMAGE
ARG BUILD_IMAGE

FROM --platform=${TARGETPLATFORM} $BUILD_IMAGE AS base
WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

FROM base AS build
ARG TARGETOS
ARG TARGETARCH
ENV VERSION_PKG=sigs.k8s.io/aws-load-balancer-controller/pkg/version
RUN --mount=type=bind,target=. \
    GIT_VERSION=$(git describe --tags --dirty --always) \
    GIT_COMMIT=$(git rev-parse HEAD) \
    BUILD_DATE=$(date +%Y-%m-%dT%H:%M:%S%z) \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} GO111MODULE=on \
    go build -gcflags="all=-N -l" -ldflags="-X ${VERSION_PKG}.GitVersion=${GIT_VERSION} -X ${VERSION_PKG}.GitCommit=${GIT_COMMIT} -X ${VERSION_PKG}.BuildDate=${BUILD_DATE}" -mod=readonly -a -o /out/controller main.go

FROM $BASE_IMAGE as bin-unix

COPY --from=build /out/controller /controller

FROM bin-unix AS bin-linux
FROM bin-unix AS bin-darwin

FROM bin-${TARGETOS} as bin-pre

# ---

FROM golang:1.24.2-alpine AS debugging

RUN GOOS=linux GOARCH=arm64 go install github.com/go-delve/delve/cmd/dlv@latest

FROM bin-pre as bin
COPY --from=debugging /go/bin/dlv /dlv
ENTRYPOINT ["/dlv", "--listen=:4000", "--headless=true", "--api-version=2", "exec", "/controller", "--"]
