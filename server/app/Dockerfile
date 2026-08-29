FROM node:20-alpine

WORKDIR /app

RUN npm install --global pnpm@10.12.1

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

COPY src ./src

ENV NODE_ENV=production
EXPOSE 3000

USER node

CMD ["pnpm", "start"]
