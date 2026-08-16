# syntax=docker/dockerfile:1

ARG MISE_VERSION=2026.8.6
ARG MISE_SHA256=cfe49784ec9683b38510846958cfecd9b59da84d4e8a38d18ffda19dc2941ead

# The web build is the same bytes for every architecture. Only amd64 is
# published, and this keeps the compiler off an emulated runner if another
# platform is ever added, where only the nginx stage below is per platform.
FROM --platform=$BUILDPLATFORM debian:13-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258 AS sdk

ARG MISE_VERSION
ARG MISE_SHA256
ARG DEBIAN_FRONTEND=noninteractive
ENV MISE_DATA_DIR=/opt/mise \
	PATH="/opt/flutter/bin:${PATH}"

RUN apt-get update \
	&& apt-get install -qy --no-install-recommends \
		ca-certificates \
		curl \
		git \
		python3 \
		unzip \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/mise.tar.gz \
		"https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64.tar.gz" \
	&& echo "${MISE_SHA256}  /tmp/mise.tar.gz" | sha256sum -c - \
	&& tar -xzf /tmp/mise.tar.gz -C /usr/local --strip-components=1 mise/bin/mise \
	&& rm /tmp/mise.tar.gz \
	&& mise --version

WORKDIR /src

COPY mise.toml mise.lock ./
RUN mise trust mise.toml \
	&& mise install flutter --locked \
	&& ln -s "$(mise where flutter)" /opt/flutter \
	&& git config --global --add safe.directory /opt/flutter \
	&& flutter --version

FROM sdk AS build

WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY lib ./lib
COPY web ./web
COPY tools ./tools

RUN python3 tools/web_assets.py

ARG API=/api

RUN flutter build web --release --no-web-resources-cdn --dart-define=api="${API}"

RUN find build/web -type f \
		\( -name '*.js' -o -name '*.css' -o -name '*.html' -o -name '*.json' \
		-o -name '*.wasm' -o -name '*.svg' \) \
		-size +1k -exec gzip -9 -k -f {} +

FROM nginxinc/nginx-unprivileged:1.31.3-alpine@sha256:334d92979f15aaecd5dd50af5105e1230e2bb70765d45b1e2f964e7c5eda81c3 AS runtime

LABEL org.opencontainers.image.title="DGS Lernen" \
	  org.opencontainers.image.description="Deutsche Gebärdensprache lernen mit Videos von SignDict." \
	  org.opencontainers.image.source="https://github.com/DoPri/gebaerden" \
	  org.opencontainers.image.licenses="GPL-3.0-or-later"

ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
	NGINX_ENVSUBST_FILTER='^(NGINX_LOCAL_RESOLVERS|API_UPSTREAM)$' \
	API_UPSTREAM=https://signdict.org/graphql-api

COPY docker/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/build/web /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
	CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
