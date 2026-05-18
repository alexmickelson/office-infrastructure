FROM nousresearch/hermes-agent:latest

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /nix && chown 10000:10000 /nix
RUN mkdir -p /home/hermes && chown 10000:10000 /home/hermes

ENV PATH=/home/hermes/.nix-profile/bin:/opt/hermes/.venv/bin:$PATH
ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

USER hermes

COPY --chown=hermes:hermes entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway", "run"]
