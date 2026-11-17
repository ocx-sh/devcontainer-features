# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Interpreters (dash, busybox, bash) and test tools for the unit suite; the repo is bind-mounted.
FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash dash busybox-static coreutils jq sed grep gawk findutils \
    && rm -rf /var/lib/apt/lists/*
