# Docker S3 Backup

Автоматическое резервное копирование Docker-проектов в S3-хранилище по расписанию.

## Что делает

- Создаёт полный архив директории проекта
- Загружает в S3-совместимое хранилище (Yandex Cloud, Timeweb, AWS S3, MinIO)
- Работает по расписанию cron (по умолчанию: каждый день в 05:00 МСК)
- Хранит только последние N версий бэкапов (по умолчанию: 30)
- Сохраняет бекапы в папку с именем проекта: `s3://bucket/project-name/`
- Опционально останавливает сервисы перед бекапом

## Быстрый старт

Создайте `docker-compose.yaml`:

```yaml
services:
  backup:
    image: ghcr.io/gromov-io/docker-s3-backup:latest
    container_name: project-backup
    restart: unless-stopped
    environment:
      - BACKUP_PROJECT_NAME=my-project
      - BACKUP_S3_BUCKET=my-backups
      - BACKUP_S3_ENDPOINT=s3.twcstorage.ru
      - BACKUP_S3_ACCESS_KEY=your_key
      - BACKUP_S3_SECRET_KEY=your_secret
    volumes:
      - .:/backup-source:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

Запустите:

```bash
docker compose up -d backup
```

**По умолчанию:**
- Часовой пояс: `Europe/Moscow`
- Расписание: каждый день в `05:00`
- Хранение: `30` последних версий
- Папка в S3: `{project-name}/`

## Ручной запуск бекапа

```bash
docker exec project-backup /scripts/backup.sh
```

## Переменные окружения

### Обязательные

| Переменная | Описание | Пример |
|------------|----------|--------|
| `BACKUP_S3_BUCKET` | S3 бакет | `my-backups` |
| `BACKUP_S3_ENDPOINT` | S3 эндпоинт | `s3.twcstorage.ru` |
| `BACKUP_S3_ACCESS_KEY` | Ключ доступа | `your_key` |
| `BACKUP_S3_SECRET_KEY` | Секретный ключ | `your_secret` |

### Опциональные

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `TZ` | `Europe/Moscow` | Часовой пояс |
| `BACKUP_PROJECT_NAME` | `project` | Имя проекта |
| `BACKUP_SCHEDULE` | `0 5 * * *` | Расписание cron |
| `BACKUP_RETENTION_COUNT` | `30` | Количество версий |
| `BACKUP_S3_REGION` | `ru-1` | Регион S3 |
| `BACKUP_S3_FOLDER` | `{project}` | Папка в бакете |
| `BACKUP_ON_START` | `false` | Бекап при старте |
| `BACKUP_STOP_SERVICES` | - | Сервисы для остановки |


## Полезные команды

**Просмотр логов:**
```bash
docker logs -f project-backup
docker exec project-backup tail -f /var/log/backup.log
```

**Проверка S3:**
```bash
docker exec project-backup aws s3 ls s3://your-bucket --endpoint-url=https://your-endpoint
```


## Расписания cron

```yaml
# Каждый день в 05:00
- BACKUP_SCHEDULE=0 5 * * *

# Каждые 6 часов
- BACKUP_SCHEDULE=0 */6 * * *

# Каждое воскресенье в 02:00
- BACKUP_SCHEDULE=0 2 * * 0

# Каждые 30 минут
- BACKUP_SCHEDULE=*/30 * * * *
```

## Остановка сервисов

Для консистентности данных можно останавливать сервисы:

```yaml
environment:
  - BACKUP_STOP_SERVICES=app db
```

Сервисы автоматически запустятся после создания архива.


## Лицензия

MIT

