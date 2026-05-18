FROM nousresearch/hermes-agent:latest

# Create /nix mount point for the persistent volume
RUN mkdir -p /nix

ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Ensure non-interactive bash shells (e.g. `bash -c`) also load the Nix profile
ENV BASH_ENV=/etc/profile.d/nix-hermes.sh

COPY .bashrc /etc/hermes-bashrc
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
