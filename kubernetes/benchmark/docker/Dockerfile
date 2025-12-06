FROM alpine/k8s:1.28.2
RUN apk --no-cache add hey curl jq \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

WORKDIR /app

COPY ../scripts/benchmark.sh .
RUN chmod +x benchmark.sh

ENTRYPOINT ["/bin/sh"]
