#!/bin/bash

echo "================================================"
echo "Universal Docker Project Backup Service"
echo "================================================"
echo "Project: ${BACKUP_PROJECT_NAME:-project}"
echo "Source Path: ${BACKUP_SOURCE_PATH:-.} (mounted as /backup-source)"
echo "Timezone: ${TZ:-Europe/Moscow}"
echo "Backup Schedule: ${BACKUP_SCHEDULE:-0 5 * * *}"
echo "S3 Endpoint: ${BACKUP_S3_ENDPOINT:-не указан}"
echo "S3 Bucket: ${BACKUP_S3_BUCKET:-не указан}"
echo "Retention Count: ${BACKUP_RETENTION_COUNT:-30} последних версий"
echo "Backup Type: Full project directory"
if [ -n "$BACKUP_STOP_SERVICES" ]; then
    echo "Services to stop: ${BACKUP_STOP_SERVICES}"
    echo "Compose file: /backup-source/docker-compose.yml (auto-detect)"
fi
echo "================================================"

# Проверка обязательных переменных
if [ -z "$BACKUP_S3_BUCKET" ] || [ -z "$BACKUP_S3_ACCESS_KEY" ] || [ -z "$BACKUP_S3_SECRET_KEY" ]; then
    echo "ERROR: Не заданы обязательные переменные окружения для S3!"
    echo "Необходимо указать: BACKUP_S3_BUCKET, BACKUP_S3_ACCESS_KEY, BACKUP_S3_SECRET_KEY"
    exit 1
fi

# Создаем crontab файл с заданным расписанием
echo "${BACKUP_SCHEDULE:-0 5 * * *} /scripts/backup.sh >> /var/log/backup.log 2>&1" > /scripts/crontab

echo "Расписание установлено: ${BACKUP_SCHEDULE:-0 5 * * *}"
echo "Логи сохраняются в: /var/log/backup.log"
echo "================================================"

# Опционально: запускаем первый бэкап сразу при старте
if [ "${BACKUP_ON_START:-false}" = "true" ]; then
    echo "Запуск начального бэкапа..."
    /scripts/backup.sh >> /var/log/backup.log 2>&1
fi

echo "Запуск supercronic..."
echo "Контейнер запущен и ожидает выполнения по расписанию"
echo "================================================"

# Запускаем supercronic в foreground режиме
exec supercronic /scripts/crontab

