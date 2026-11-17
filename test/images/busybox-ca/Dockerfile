# busybox:musl plus a CA bundle: bare busybox has no package manager and no certificates, so no
# network install can work on it. The bundle comes from a pinned alpine stage. Renovate may bump both tags.
FROM alpine:3.24 AS ca

FROM busybox:1.37-musl
COPY --from=ca /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
