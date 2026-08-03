FROM node:18-alpine AS build

WORKDIR /app

# Ставим зависимости строго по lock-файлу - воспроизводимая сборка.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# CRA вшивает REACT_APP_* в бандл на этапе сборки.
# Пустое значение = относительные пути (запросы через nginx на тот же origin).
ARG REACT_APP_API_URL=""
ENV REACT_APP_API_URL=$REACT_APP_API_URL

RUN npm run build

FROM node:18-alpine

WORKDIR /app
RUN npm install -g serve@14

COPY --from=build /app/build ./build

EXPOSE 3000

# -s: SPA-режим, любой неизвестный путь отдаёт index.html (нужно для react-router).
CMD ["serve", "-s", "build", "-l", "3000"]
