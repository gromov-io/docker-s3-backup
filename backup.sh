#!/bin/bash

#######################################################
# Universal Docker Project Backup Script
# Архивирует проект и загружает в S3
#######################################################

set -e  # Остановка при ошибке

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" >&2
}

# Проверка обязательных переменных окружения
check_env_vars() {
    local missing_vars=()
    
    if [ -z "$BACKUP_S3_BUCKET" ]; then missing_vars+=("BACKUP_S3_BUCKET"); fi
    if [ -z "$BACKUP_S3_ACCESS_KEY" ]; then missing_vars+=("BACKUP_S3_ACCESS_KEY"); fi
    if [ -z "$BACKUP_S3_SECRET_KEY" ]; then missing_vars+=("BACKUP_S3_SECRET_KEY"); fi
    if [ -z "$BACKUP_S3_ENDPOINT" ]; then missing_vars+=("BACKUP_S3_ENDPOINT"); fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Отсутствуют обязательные переменные окружения: ${missing_vars[*]}"
        exit 1
    fi
}

# Настройка AWS CLI для работы с S3
configure_aws() {
    log "Настройка AWS CLI..."
    
    export AWS_ACCESS_KEY_ID="$BACKUP_S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$BACKUP_S3_SECRET_KEY"
    export AWS_DEFAULT_REGION="${BACKUP_S3_REGION:-ru-1}"
    
    # Для S3-совместимых хранилищ (Yandex, Minio и т.д.)
    if [ -n "$BACKUP_S3_ENDPOINT" ]; then
        AWS_ENDPOINT_ARG="--endpoint-url=https://${BACKUP_S3_ENDPOINT}"
    else
        AWS_ENDPOINT_ARG=""
    fi
}

# Остановка сервисов перед бекапом
stop_services() {
    if [ -z "$BACKUP_STOP_SERVICES" ]; then
        log "Список сервисов для остановки не указан, пропускаем..."
        return 0
    fi
    
    # Определяем project name из собственных labels контейнера
    local project_name=$(docker inspect "$HOSTNAME" --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null)
    
    if [ -z "$project_name" ]; then
        log_warning "Не удалось определить project name автоматически"
        log_warning "Контейнер backup должен быть запущен из того же docker-compose.yaml что и целевые сервисы"
        return 0
    fi
    
    log "Project name определён автоматически: ${project_name}"
    log "Остановка сервисов: ${BACKUP_STOP_SERVICES}"
    
    # Запоминаем ID контейнеров для последующего запуска
    CONTAINERS_TO_RESTART=""
    
    for service in $BACKUP_STOP_SERVICES; do
        # Ищем контейнер по service name + project name + статус running
        local container_id=$(docker ps \
            --filter "label=com.docker.compose.service=${service}" \
            --filter "label=com.docker.compose.project=${project_name}" \
            --filter "status=running" \
            --format "{{.ID}}" \
            | head -n1)
        
        if [ -n "$container_id" ]; then
            local container_name=$(docker inspect "$container_id" --format '{{.Name}}' | sed 's/^\///')
            log "Сервис ${service} (контейнер: ${container_name}) запущен, будет остановлен"
            
            # Останавливаем контейнер
            docker stop "$container_id" >/dev/null 2>&1 || {
                log_error "Ошибка при остановке контейнера ${container_name}"
                return 1
            }
            
            # Запоминаем ID для последующего запуска
            CONTAINERS_TO_RESTART="${CONTAINERS_TO_RESTART} ${container_id}"
        else
            log "Сервис ${service} не запущен или не найден, пропускаем"
        fi
    done
    
    if [ -n "$CONTAINERS_TO_RESTART" ]; then
        log "Контейнеры успешно остановлены"
    else
        log "Нет запущенных сервисов для остановки"
    fi
    
    # Даем время на корректное завершение
    sleep 5
    
    return 0
}

# Запуск сервисов после бекапа
start_services() {
    if [ -z "$BACKUP_STOP_SERVICES" ]; then
        return 0
    fi
    
    # Проверяем что есть контейнеры для запуска
    if [ -z "$CONTAINERS_TO_RESTART" ]; then
        log "Нет контейнеров для запуска"
        return 0
    fi
    
    log "Запуск контейнеров..."
    
    # Запускаем только те контейнеры, которые были остановлены
    for container_id in $CONTAINERS_TO_RESTART; do
        local container_name=$(docker inspect "$container_id" --format '{{.Name}}' 2>/dev/null | sed 's/^\///')
        
        if [ -n "$container_name" ]; then
            log "Запуск контейнера: ${container_name}"
            docker start "$container_id" >/dev/null 2>&1 || {
                log_error "Ошибка при запуске контейнера ${container_name}"
                return 1
            }
        fi
    done
    
    log "Контейнеры успешно запущены"
    
    return 0
}

# Создание архива
create_backup() {
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    
    # Имя проекта берется из переменной окружения
    local project_name="${BACKUP_PROJECT_NAME:-project}"
    local backup_filename="${project_name}-backup-${timestamp}.tar.gz"
    local backup_path="/tmp/${backup_filename}"
    
    log "Начинается создание полного бэкапа проекта: ${backup_filename}"
    log "Проект: ${project_name}"
    log "Архивируется вся директория /backup-source/"
    
    # Создаем полный архив всей директории БЕЗ ИСКЛЮЧЕНИЙ
    log "Создание tar.gz архива..."
    tar -czf "$backup_path" \
        -C /backup-source \
        --transform "s,^,${project_name}/," \
        . || {
        log_error "Ошибка создания архива"
        return 1
    }
    
    # Получаем размер архива
    local backup_size=$(du -h "$backup_path" | cut -f1)
    log "Полный архив создан успешно: ${backup_filename} (размер: ${backup_size})"
    
    # Возвращаем путь через глобальную переменную
    BACKUP_FILE_PATH="$backup_path"
    return 0
}

# Загрузка архива в S3
upload_to_s3() {
    local backup_path="$1"
    
    # Проверка существования файла
    if [ ! -f "$backup_path" ]; then
        log_error "Файл бэкапа не найден: $backup_path"
        return 1
    fi
    
    local backup_filename=$(basename "$backup_path")
    local project_name="${BACKUP_PROJECT_NAME:-project}"
    
    # Формируем путь с учетом BACKUP_S3_FOLDER
    # По умолчанию используется имя проекта как папка
    local s3_folder="${BACKUP_S3_FOLDER:-$project_name}"
    
    # Удаляем начальный и конечный слэш, если есть
    s3_folder="${s3_folder#/}"
    s3_folder="${s3_folder%/}"
    
    local s3_path="s3://${BACKUP_S3_BUCKET}/${s3_folder}/${backup_filename}"
    
    log "Загрузка бэкапа в S3: ${s3_path}"
    
    aws s3 cp "$backup_path" "$s3_path" $AWS_ENDPOINT_ARG || {
        log_error "Ошибка загрузки в S3"
        return 1
    }
    
    log "Бэкап успешно загружен в S3"
}

# Удаление старых бэкапов из S3
cleanup_old_backups() {
    local retention_count="${BACKUP_RETENTION_COUNT:-30}"
    
    log "Очистка старых бэкапов (храним последние ${retention_count} версий)..."
    
    # Формируем путь с учетом BACKUP_S3_FOLDER
    # По умолчанию используется имя проекта как папка
    local project_name="${BACKUP_PROJECT_NAME:-project}"
    local s3_folder="${BACKUP_S3_FOLDER:-$project_name}"
    
    # Удаляем начальный и конечный слэш, если есть
    s3_folder="${s3_folder#/}"
    s3_folder="${s3_folder%/}"
    
    local s3_list_path="s3://${BACKUP_S3_BUCKET}/${s3_folder}/"
    
    # Получаем список всех бэкапов и сортируем по дате (новые первые)
    local backup_list=$(aws s3 ls "${s3_list_path}" $AWS_ENDPOINT_ARG | grep "\-backup-" | awk '{print $4}' | sort -r)
    
    if [ -z "$backup_list" ]; then
        log "Бэкапы не найдены"
        return 0
    fi
    
    local total_backups=$(echo "$backup_list" | wc -l)
    log "Найдено бэкапов: ${total_backups}"
    
    # Если бэкапов меньше или равно лимиту, ничего не удаляем
    if [ "$total_backups" -le "$retention_count" ]; then
        log "Количество бэкапов в пределах лимита, удаление не требуется"
        return 0
    fi
    
    # Удаляем старые бэкапы (все после N последних)
    local deleted_count=0
    local index=0
    
    echo "$backup_list" | while read -r filename; do
        index=$((index + 1))
        
        # Пропускаем первые N (самые новые)
        if [ "$index" -le "$retention_count" ]; then
            continue
        fi
        
        log "Удаление старого бэкапа: ${filename}"
        aws s3 rm "s3://${BACKUP_S3_BUCKET}/${s3_folder}/${filename}" $AWS_ENDPOINT_ARG || {
            log_warning "Не удалось удалить ${filename}"
        }
        deleted_count=$((deleted_count + 1))
    done
    
    log "Очистка завершена"
}

# Основная функция
main() {
    log "=========================================="
    log "Запуск процесса бэкапа проекта"
    log "=========================================="
    
    # Проверка переменных окружения
    check_env_vars
    
    # Настройка AWS CLI
    configure_aws
    
    # Остановка сервисов перед бекапом
    stop_services || {
        log_error "Не удалось остановить сервисы"
        exit 1
    }
    
    # Создание бэкапа
    create_backup || {
        log_error "Не удалось создать бэкап"
        # Пытаемся запустить сервисы обратно даже при ошибке
        start_services
        exit 1
    }
    
    # Запуск сервисов после создания бекапа
    start_services || {
        log_warning "Не удалось запустить сервисы, но бэкап создан"
    }
    
    # Загрузка в S3
    upload_to_s3 "$BACKUP_FILE_PATH" || {
        log_error "Не удалось загрузить бэкап в S3"
        rm -f "$BACKUP_FILE_PATH"
        exit 1
    }
    
    # Очистка временного файла
    rm -f "$BACKUP_FILE_PATH"
    log "Временный файл удален"
    
    # Очистка всех старых временных файлов бэкапа из /tmp
    log "Очистка старых временных файлов..."
    find /tmp -name "*-backup-*.tar.gz" -type f -mmin +60 -delete 2>/dev/null || true
    
    # Очистка старых бэкапов
    cleanup_old_backups
    
    log "=========================================="
    log "Бэкап завершен успешно!"
    log "=========================================="
}

# Запуск
main

