FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY wrangler.toml ./
COPY src/ src/

EXPOSE 8787

CMD ["npx", "wrangler", "dev", "--host", "0.0.0.0", "--port", "8787"]
