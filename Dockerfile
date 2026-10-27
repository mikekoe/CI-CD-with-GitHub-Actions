# DevOps tool image
#   docker build -t devops-tool .
#   docker run --rm devops-tool help
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="devops-tool" \
      org.opencontainers.image.description="Bash DevOps tool: system-info, check-host, check-port"

# Only what check-host and check-port need (ping and nc).
# getent, df and the rest ship with the base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends iputils-ping netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user
RUN useradd --system --create-home --shell /usr/sbin/nologin devops

WORKDIR /app
COPY app/ /app/
RUN chmod 0755 /app/app.sh

USER devops

# `docker run devops-tool system-info`  ->  /app/app.sh system-info
ENTRYPOINT ["/app/app.sh"]
CMD ["help"]
