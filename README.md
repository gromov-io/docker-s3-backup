# 🗄️ Universal Docker Backup Service

Универсальная система автоматического резервного копирования Docker-проектов с загрузкой в S3-совместимое хранилище.

## ✨ Возможности

- ✅ Автоматическое создание tar.gz архивов по расписанию (cron)
- ✅ Загрузка бэкапов в S3-совместимые хранилища (Yandex Cloud, AWS S3, MinIO, Timeweb и т.д.)
- ✅ Опциональная остановка сервисов перед бекапом для консистентности данных
- ✅ Автоматическое удаление старых бэкапов
- ✅ Подробное логирование всех операций
- ✅ Запуск в отдельном Docker-контейнере

## 🚀 Быстрый старт

### 1. Подготовка

Скопируйте файлы в директорию вашего проекта, который нужно бекапить:

```bash
git clone <this-repo> backup-system
cd your-project
cp -r backup-system/* .
```

### 2. Настройка

Отредактируйте `docker-compose.yaml` и укажите свои значения переменных окружения:

```yaml
environment:
  # Обязательные параметры
  - BACKUP_PROJECT_NAME=my-project
  - BACKUP_S3_BUCKET=my-backups
  - BACKUP_S3_ENDPOINT=s3.twcstorage.ru
  - BACKUP_S3_ACCESS_KEY=your_access_key
  - BACKUP_S3_SECRET_KEY=your_secret_key
  
  # Необязательные параметры
  - BACKUP_SCHEDULE=0 3 * * *  # Каждый день в 03:00
  - BACKUP_RETENTION_DAYS=30
```

### 3. Запуск

```bash
docker compose up -d backup
```

Проверить логи:

```bash
docker compose logs -f backup
```

## 📋 Переменные окружения

Все параметры подробно описаны в `docker-compose.yaml` с примерами использования.

### Обязательные параметры

| Параметр | Описание | Пример |
|----------|----------|--------|
| `BACKUP_S3_BUCKET` | Имя S3 бакета | `my-backups` |
| `BACKUP_S3_ENDPOINT` | Эндпоинт S3 сервиса | `s3.twcstorage.ru` |
| `BACKUP_S3_ACCESS_KEY` | Ключ доступа S3 | `your_key` |
| `BACKUP_S3_SECRET_KEY` | Секретный ключ S3 | `your_secret` |

### Необязательные параметры

| Параметр | Значение по умолчанию | Описание |
|----------|----------------------|----------|
| `BACKUP_PROJECT_NAME` | `project` | Имя проекта для архивов |
| `BACKUP_S3_FOLDER` | ` ` (корень) | Папка внутри бакета |
| `BACKUP_S3_REGION` | `ru-1` | Регион S3 |
| `BACKUP_RETENTION_DAYS` | `30` | Дни хранения бэкапов |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Расписание cron |
| `BACKUP_ON_START` | `false` | Бекап при старте |
| `BACKUP_STOP_SERVICES` | ` ` | Сервисы для остановки |
| `BACKUP_COMPOSE_FILE` | ` ` | Путь к compose-файлу |

## 🛠️ Расширенные сценарии

### Остановка сервисов перед бекапом

Для консистентности данных можно останавливать сервисы перед созданием архива:

```yaml
environment:
  # ... другие параметры ...
  - BACKUP_STOP_SERVICES=gitea gitea-db
  - BACKUP_COMPOSE_FILE=/backup-source/docker-compose.yml
```

**Важно:**
- Сервисы будут остановлены через `docker compose down`
- После создания архива сервисы автоматически запустятся через `docker compose up -d`
- Если бекап упадет с ошибкой - сервисы все равно запустятся обратно

### Изменение директории для бекапа

По умолчанию бекапится текущая директория (`.`). Чтобы изменить:

```yaml
volumes:
  - /path/to/your/project:/backup-source:ro
  # ... остальные volumes ...
```

### Примеры расписаний (cron)

```yaml
# Каждый день в 03:00
- BACKUP_SCHEDULE=0 3 * * *

# Каждые 6 часов
- BACKUP_SCHEDULE=0 */6 * * *

# Каждое воскресенье в 02:00
- BACKUP_SCHEDULE=0 2 * * 0

# Каждые 30 минут
- BACKUP_SCHEDULE=*/30 * * * *

# Дважды в день: 03:00 и 15:00
- BACKUP_SCHEDULE=0 3,15 * * *
```

### Тестовый бекап

Для проверки настроек запустите бекап вручную:

```bash
docker compose exec backup /scripts/backup.sh
```

Или включите бекап при старте:

```yaml
- BACKUP_ON_START=true
```

## 📂 Формат архивов

Архивы создаются в формате:

```
{BACKUP_PROJECT_NAME}-backup-YYYY-MM-DD_HH-MM-SS.tar.gz
```

Пример: `my-project-backup-2025-10-22_03-00-00.tar.gz`

## 🔧 Структура проекта

```
.
├── backup.sh          # Основной скрипт бекапа
├── entrypoint.sh      # Точка входа контейнера
├── crontab            # Шаблон cron (генерируется автоматически)
├── Dockerfile         # Образ контейнера
├── docker-compose.yaml # Конфигурация сервиса
└── README.md          # Документация
```

## 🐛 Решение проблем

### Проверка логов

```bash
# Все логи
docker compose logs backup

# Логи в реальном времени
docker compose logs -f backup

# Внутренние логи бекапа
docker compose exec backup cat /var/log/backup.log
```

### Проверка доступа к S3

```bash
docker compose exec backup aws s3 ls s3://your-bucket --endpoint-url=https://your-endpoint
```

### Ручной запуск бекапа

```bash
docker compose exec backup /scripts/backup.sh
```

## 📊 S3-провайдеры

### Yandex Cloud Object Storage

```yaml
- BACKUP_S3_ENDPOINT=storage.yandexcloud.net
- BACKUP_S3_REGION=ru-central1
```

### Timeweb Cloud S3

```yaml
- BACKUP_S3_ENDPOINT=s3.twcstorage.ru
- BACKUP_S3_REGION=ru-1
```

### AWS S3

```yaml
- BACKUP_S3_ENDPOINT=s3.amazonaws.com
- BACKUP_S3_REGION=us-east-1
```

### MinIO (self-hosted)

```yaml
- BACKUP_S3_ENDPOINT=minio.your-domain.com
- BACKUP_S3_REGION=us-east-1
```

## 📝 Лицензия

MIT

## 🤝 Поддержка

При возникновении проблем создайте issue в репозитории.

