# UncleCred render and generation worker. FFmpeg plus Chromium for Remotion. Runs on Railway.
FROM node:20-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg chromium fonts-liberation ca-certificates && rm -rf /var/lib/apt/lists/*
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium REMOTION_CHROME_EXECUTABLE=/usr/bin/chromium
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && pnpm install --frozen-lockfile || pnpm install
COPY . .
CMD ["pnpm", "start"]
