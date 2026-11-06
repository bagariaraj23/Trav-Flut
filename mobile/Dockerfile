# Flutter web UI for the local Docker stack.
# The browser talks to nginx on :8080, which proxies /api, /chat, and /share
# to the backend container. API_BASE_URL is therefore a host URL, not a
# Compose service name.

ARG FLUTTER_IMAGE_TAG=3.38.5
FROM ghcr.io/cirruslabs/flutter:${FLUTTER_IMAGE_TAG} AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
COPY scripts/linux_mapbox_pub_get.sh scripts/linux_mapbox_pub_get.sh
# Mapbox 3.x is Swift Package Manager only. Linux Flutter exits 1 on that
# check; the script adds a pub-cache podspec placeholder and retries.
RUN sh scripts/linux_mapbox_pub_get.sh

COPY . .

ARG API_BASE_URL=http://localhost:8080/api
ARG SHARE_LINK_BASE_URL=http://localhost:8080
ARG MAPBOX_ACCESS_TOKEN=
ARG GOOGLE_CLIENT_ID=

# pubspec.yaml bundles .env. AppConfig prefers that file over dart-define.
RUN printf '%s\n' \
  "API_BASE_URL=${API_BASE_URL}" \
  "SHARE_LINK_BASE_URL=${SHARE_LINK_BASE_URL}" \
  "ENVIRONMENT=development" \
  "MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN}" \
  "GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}" \
  > .env

RUN flutter build web --release --pwa-strategy=none --no-wasm-dry-run \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=SHARE_LINK_BASE_URL="${SHARE_LINK_BASE_URL}" \
  --dart-define=ENVIRONMENT=development \
  --dart-define=MAPBOX_ACCESS_TOKEN="${MAPBOX_ACCESS_TOKEN}" \
  --dart-define=GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}"

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
