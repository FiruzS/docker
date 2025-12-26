# Dockerfile для приложения Joomla + MySQL
# Этот образ будет содержать полное приложение из docker-compose

# Используем официальный образ Joomla
FROM joomla:4-apache

# Устанавливаем дополнительные утилиты для отладки
RUN apt-get update && \
    apt-get install -y \
    curl \
    wget \
    nano \
    htop \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Копируем скрипт мониторинга
COPY docker_monitor.sh /usr/local/bin/docker_monitor.sh
RUN chmod +x /usr/local/bin/docker_monitor.sh

# Копируем docker-compose файл (для информации)
COPY docker-compose.yml /app/docker-compose.yml

# Создаем healthcheck скрипт
RUN echo '#!/bin/bash\ncurl -f http://localhost/ || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# Указываем healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/healthcheck.sh"]

# Экспонируем порт 80
EXPOSE 80

# Добавляем метаданные
LABEL maintainer="ваше-имя"
LABEL description="Joomla приложение с мониторингом"
LABEL version="1.0"

# Стандартная команда запуска Joomla
CMD ["apache2-foreground"]
