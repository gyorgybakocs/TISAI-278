ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root

# Install necessary tools for orchestration scripts
# bash: required for complex init scripts
# gettext: provides 'envsubst' for config templating
# procps: provides 'ps' for process monitoring
# coreutils: provides robust 'cp', 'mv', 'sort'
RUN apk add --no-cache bash gettext procps coreutils

# Create directory for custom scripts
RUN mkdir -p /opt/tis/scripts && \
    chown -R redis:redis /opt/tis/scripts

USER redis
