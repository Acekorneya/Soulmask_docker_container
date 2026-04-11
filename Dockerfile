FROM debian:12-slim

ARG POKUSER_UID=1000
ARG POKUSER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV HOME=/home/pokuser

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        lib32gcc-s1 \
        libnss-wrapper \
        locales \
        procps \
        tini \
        util-linux \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && groupadd -g "${POKUSER_GID}" pokuser \
    && useradd -m -u "${POKUSER_UID}" -g "${POKUSER_GID}" -s /bin/bash pokuser \
    && mkdir -p /home/pokuser/soulmask/config /home/pokuser/soulmask/instances /home/pokuser/soulmask/shared \
    && chown -R "${POKUSER_UID}:${POKUSER_GID}" /home/pokuser \
    && chmod 1777 /home/pokuser/soulmask/config /home/pokuser/soulmask/instances /home/pokuser/soulmask/shared \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh

WORKDIR /home/pokuser

USER pokuser

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
