# run this command to build the backend Docker image: ` docker build -t todo-mono-repo -f ./docker/Dockerfile.backend . `
FROM oven/bun:1

WORKDIR /usr/src/app

COPY ./packages ./packages
COPY ./bun.lock ./bun.lock

COPY ./package.json ./package.json
COPY ./turbo.json ./turbo.json

COPY ./apps/ws ./apps/ws

RUN bun install
RUN bun run db:generate

EXPOSE 8081

CMD ["bun", "run", "start:ws"]
