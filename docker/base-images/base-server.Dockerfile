ARG BASE_IMAGE=alpine:3.19

##### base-server target #####
FROM ${BASE_IMAGE} AS base-server

RUN apk add --update --no-cache \
    ca-certificates \
    tzdata \
    bash \
    curl

SHELL ["/bin/bash", "-c"]
