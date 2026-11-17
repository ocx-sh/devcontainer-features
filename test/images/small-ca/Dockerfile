# debian with curl, an EMPTY system certificate store and one small PEM (a few well-known roots, far
# under the 32 KiB ocx accepts) at /etc/ocx-test/ca.pem. The caBundle scenario can only build when
# the feature downloads through that file. The roots cover github.com, its release CDN and setup.ocx.sh.
FROM debian:stable-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && mkdir -p /etc/ocx-test \
    && for c in ISRG_Root_X1 ISRG_Root_X2 USERTrust_ECC_Certification_Authority USERTrust_RSA_Certification_Authority \
        DigiCert_Global_Root_G2 DigiCert_Global_Root_CA DigiCert_High_Assurance_EV_Root_CA Amazon_Root_CA_1 GTS_Root_R1 GTS_Root_R4; do \
        cat "/usr/share/ca-certificates/mozilla/$c.crt"; \
    done >/etc/ocx-test/ca.pem \
    && [ "$(wc -c </etc/ocx-test/ca.pem)" -lt 32768 ] \
    && rm -rf /etc/ssl/certs/* /usr/share/ca-certificates/* /var/lib/apt/lists/*
