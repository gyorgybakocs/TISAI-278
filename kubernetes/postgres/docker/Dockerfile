ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext-base && \
    rm -rf /var/lib/apt/lists/*

# Copy configuration template
COPY kubernetes/postgres/config/postgresql.conf.template /etc/postgresql/postgresql.conf.template
COPY kubernetes/postgres/config/pg_hba.conf      /etc/postgresql/pg_hba.conf

# Copy and setup entrypoint script
COPY kubernetes/postgres/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /etc/postgresql && \
    chown -R postgres:postgres /etc/postgresql && \
    chmod 755 /etc/postgresql

USER postgres

ENTRYPOINT ["/entrypoint.sh"]
CMD ["postgres","-c","config_file=/etc/postgresql/postgresql.conf","-c","hba_file=/etc/postgresql/pg_hba.conf"]
