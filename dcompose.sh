#!/bin/bash

set -e

# 1. Подготовка
mkdir -p /opt/docker/dockercompose/task-13
cd /opt/docker/dockercompose

# 2. Установка docker-compose (если ещё не установлен)
if ! command -v docker-compose &> /dev/null; then
    echo "Устанавливаем docker-compose..."
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 3. Создание сети
docker network create dockercompose-frontend || true

# 4. Dockerfile для phpmyadmin (frontend)
mkdir -p frontend
cat > frontend/Dockerfile <<EOF
FROM phpmyadmin:5.2.0-apache
RUN apt-get update && apt-get install -y iputils-ping
EOF

# 5. Dockerfile для mariadb (mydb)
mkdir -p mydb
cat > mydb/Dockerfile <<EOF
FROM mariadb:lts
RUN apt-get update && apt-get install -y iputils-ping
EOF

# 6. docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  mydb:
    build: ./mydb
    container_name: mydb
    environment:
      MYSQL_ROOT_PASSWORD: root
    volumes:
      - mydb-data:/var/lib/mysql
    networks:
      - dockercompose-frontend
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 15s
      retries: 5

  frontend:
    build: ./frontend
    container_name: phpmyadmin
    ports:
      - "8080:80"
    environment:
      PMA_HOST: mydb
      PMA_PORT: 3306
    networks:
      - dockercompose-frontend
    depends_on:
      mydb:
        condition: service_healthy

volumes:
  mydb-data:

networks:
  dockercompose-frontend:
    external: true
EOF

# 7. Запуск сервисов
docker-compose up -d --build

# 8. Ожидаем готовность mydb
echo "Ожидаем, пока mydb станет healthy..."
while [[ "$(docker inspect --format='{{.State.Health.Status}}' mydb)" != "healthy" ]]; do
  echo -n "."
  sleep 3
done
echo "mydb готов!"

# 9. SQL-операции
echo "Выполнение SQL-запросов..."
docker exec -i phpmyadmin bash -c 'echo "
create database mydb;
use mydb;
create table mytable ( id int AUTO_INCREMENT primary key, data text, datamodified timestamp default now());
insert into mytable(data) values(\"testdata01\");
insert into mytable(data) values(\"testdata02\");
insert into mytable(data) values(\"testdata03\");
" | php /etc/phpmyadmin/sql.php'

# Альтернативно, напрямую через mysql клиент в phpmyadmin (если установлен):
docker exec -i phpmyadmin bash -c 'apt-get update && apt-get install -y mariadb-client'
docker exec -i phpmyadmin bash -c 'mysql -h mydb -uroot -proot <<EOF
create database mydb;
use mydb;
create table mytable ( id int AUTO_INCREMENT primary key, data text, datamodified timestamp default now());
insert into mytable(data) values("testdata01");
insert into mytable(data) values("testdata02");
insert into mytable(data) values("testdata03");
EOF'

# 10. Дамп базы
echo "Создание дампа базы..."
docker run --rm \
  --network dockercompose-frontend \
  -v /opt/docker/dockercompose/task-13:/backup \
  -v mydb-data:/var/lib/mysql \
  mariadb:lts \
  bash -c "apt-get update && apt-get install -y mariadb-client && \
  mysqldump -h mydb -uroot -proot mydb > /backup/mydb.sql"

echo "Готово. Выполните 'checkup-compose' в /opt/docker/dockercompose для проверки."
