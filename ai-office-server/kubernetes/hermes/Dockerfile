FROM nousresearch/hermes-agent:latest

# Create /nix mount point for the persistent volume
RUN mkdir -p /nix

ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
