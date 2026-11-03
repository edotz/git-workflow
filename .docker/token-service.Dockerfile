FROM node:22-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY bin/modules/git/token-service.mjs ./bin/modules/git/token-service.mjs
COPY bin/config/token-service.json ./bin/config/token-service.json
USER node
EXPOSE 8790
CMD ["node", "bin/modules/git/token-service.mjs"]
