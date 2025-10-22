FROM alpine:latest

# Устанавливаем необходимые пакеты
RUN apk add --no-cache \
    bash \
    tar \
    gzip \
    bzip2 \
    aws-cli \
    tzdata \
    curl \
    docker-cli \
    docker-cli-compose

# Устанавливаем supercronic (cron для контейнеров)
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=cd48d45c4b10f3f0bfdd3a57d054cd05ac96812b

RUN curl -fsSLO "$SUPERCRONIC_URL" \
    && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
    && chmod +x "$SUPERCRONIC" \
    && mv "$SUPERCRONIC" "/usr/local/bin/supercronic"

# Создаем необходимые директории
RUN mkdir -p /backup-source /scripts /var/log

# Копируем скрипты
COPY backup.sh /scripts/backup.sh
COPY entrypoint.sh /scripts/entrypoint.sh
COPY crontab /scripts/crontab

# Устанавливаем права на выполнение
RUN chmod +x /scripts/backup.sh /scripts/entrypoint.sh

# Устанавливаем рабочую директорию
WORKDIR /scripts

# Запускаем entrypoint
CMD ["/scripts/entrypoint.sh"]

