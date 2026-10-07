FROM node:22-bookworm-slim AS deps
RUN apt-get update && apt-get install -y --no-install-recommends imagemagick ghostscript libheif1 libheif-dev libwebp7 libjpeg62-turbo libpng16-16 libtiff6 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm install
FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build
FROM node:22-bookworm-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends imagemagick ghostscript libheif1 libwebp7 libjpeg62-turbo libpng16-16 libtiff6 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=deps /app/node_modules ./node_modules
EXPOSE 3000
CMD ["npm","start"]