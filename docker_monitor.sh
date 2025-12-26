#!/bin/bash
# docker_monitor.sh - мониторинг ресурсов Docker-контейнеров

# Функция для показа справки
show_help() {
    echo "Использование: $0 <файл_журнала> <контейнер1> [контейнер2 ...]"
    echo ""
    echo "Примеры:"
    echo "  $0 /var/log/docker_stats.log web1 db"
    echo "  $0 ./мои_логи/контейнеры.log все"
    echo ""
    echo "Параметры:"
    echo "  'все' - мониторить все запущенные контейнеры"
    echo ""
    echo "Скрипт будет обновлять журнал каждую минуту."
    echo "Для остановки нажмите Ctrl+C"
}

# Проверяем аргументы
if [ $# -lt 2 ]; then
    echo "ОШИБКА: Недостаточно аргументов!"
    echo ""
    show_help
    exit 1
fi

LOG_FILE="$1"
shift  # Убираем первый аргумент (файл журнала)
CONTAINERS="$@"  # Все остальные аргументы - контейнеры

# Проверяем, запущен ли Docker
if ! command -v docker &> /dev/null; then
    echo "ОШИБКА: Docker не установлен или не запущен!"
    echo "Установите: sudo apt install docker.io"
    exit 1
fi

# Проверяем, запущен ли Docker демон
if ! docker info &> /dev/null; then
    echo "ОШИБКА: Docker демон не запущен!"
    echo "Запустите: sudo systemctl start docker"
    exit 1
fi

# Создаем директорию для логов, если её нет
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

# Проверяем, можно ли писать в файл
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ОШИБКА: Не могу создать/записать в файл: $LOG_FILE"
    echo "Проверьте права доступа или укажите другой путь"
    exit 1
fi

echo "====== ЗАПУСК МОНИТОРИНГА DOCKER ======"
echo "Журнал: $LOG_FILE"
echo "Контейнеры: $CONTAINERS"
echo "Время запуска: $(date '+%d-%m-%Y %H:%M:%S')"
echo "Для остановки: Ctrl+C"
echo "======================================"
echo ""

# Функция для получения статистики контейнера
get_container_stats() {
    local container="$1"
    
    # Получаем базовую информацию о контейнере
    local info=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|/||')
    
    if [ -z "$info" ]; then
        echo "Контейнер '$container' не найден!"
        return 1
    fi
    
    # Получаем статистику в реальном времени
    local stats=$(docker stats --no-stream --format \
        "table {{.Container}},{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}},{{.PIDs}}" \
        "$container" 2>/dev/null | tail -1)
    
    if [ -z "$stats" ]; then
        echo "Не удалось получить статистику для '$container'"
        return 1
    fi
    
    echo "$stats"
}

# Функция для записи заголовка в журнал
write_header() {
    echo "========================================" >> "$LOG_FILE"
    echo "Время: $(date '+%d-%m-%Y %H:%M:%S')" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    printf "%-20s %-15s %-10s %-15s %-10s %-20s %-15s %-5s\n" \
        "Контейнер" "Имя" "CPU%" "Память" "Mem%" "Сеть" "Диск" "PID" >> "$LOG_FILE"
    echo "--------------------------------------------------------------------------------------------------------" >> "$LOG_FILE"
}

# Функция для получения всех контейнеров
get_all_containers() {
    docker ps --format "{{.Names}}"
}

# Основной цикл мониторинга
MONITORING=true
trap 'MONITORING=false; echo ""; echo "Мониторинг остановлен"; exit 0' INT TERM

while $MONITORING; do
    # Записываем заголовок
    write_header
    
    # Определяем какие контейнеры мониторить
    if [ "$CONTAINERS" = "все" ]; then
        CONTAINER_LIST=$(get_all_containers)
    else
        CONTAINER_LIST="$CONTAINERS"
    fi
    
    # Счетчики
    TOTAL_CONTAINERS=0
    ACTIVE_CONTAINERS=0
    
    # Мониторим каждый контейнер
    for container in $CONTAINER_LIST; do
        TOTAL_CONTAINERS=$((TOTAL_CONTAINERS + 1))
        
        # Получаем статистику
        stats=$(get_container_stats "$container")
        
        if [ $? -eq 0 ]; then
            ACTIVE_CONTAINERS=$((ACTIVE_CONTAINERS + 1))
            
            # Парсим статистику
            container_id=$(echo "$stats" | cut -d',' -f1)
            name=$(echo "$stats" | cut -d',' -f2)
            cpu=$(echo "$stats" | cut -d',' -f3)
            mem_usage=$(echo "$stats" | cut -d',' -f4)
            mem_perc=$(echo "$stats" | cut -d',' -f5)
            net_io=$(echo "$stats" | cut -d',' -f6)
            block_io=$(echo "$stats" | cut -d',' -f7)
            pids=$(echo "$stats" | cut -d',' -f8)
            
            # Записываем в журнал
            printf "%-20s %-15s %-10s %-15s %-10s %-20s %-15s %-5s\n" \
                "${container_id:0:20}" \
                "${name:0:15}" \
                "$cpu" \
                "${mem_usage:0:15}" \
                "$mem_perc" \
                "${net_io:0:20}" \
                "${block_io:0:15}" \
                "$pids" >> "$LOG_FILE"
            
            # Выводим в консоль (опционально)
            echo "✓ $name: CPU=$cpu, Память=$mem_usage, Сеть=$net_io"
        else
            echo "✗ $container: не найден или ошибка"
            printf "%-20s %-15s %-10s %-15s %-10s %-20s %-15s %-5s\n" \
                "$container" "НЕ_НАЙДЕН" "0%" "0B" "0%" "0B" "0B" "0" >> "$LOG_FILE"
        fi
    done
    
    # Добавляем итоги
    echo "" >> "$LOG_FILE"
    echo "ИТОГО: $ACTIVE_CONTAINERS из $TOTAL_CONTAINERS контейнеров активно" >> "$LOG_FILE"
    echo "Следующее обновление через 60 секунд..." >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Выводим информацию в консоль
    echo ""
    echo "[$(date '+%H:%M:%S')] Записано в журнал. Активных: $ACTIVE_CONTAINERS/$TOTAL_CONTAINERS"
    echo "Ждем 60 секунд..."
    
    # Ждем 60 секунд
    sleep 60
done
