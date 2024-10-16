ARG UPSTREAM_IMAGE
ARG UPSTREAM_DIGEST_ARM64

FROM ${UPSTREAM_IMAGE}@${UPSTREAM_DIGEST_ARM64}
ARG IMAGE_STATS
ENV IMAGE_STATS=${IMAGE_STATS}

ARG VERSION
RUN curl -fsSL "https://github.com/engels74/tgraph-bot-source/archive/${VERSION}.tar.gz" | tar xzf - -C "${APP_DIR}" --strip-components=1 && \
    chmod -R u=rwX,go=rX "${APP_DIR}"

COPY root/ /
