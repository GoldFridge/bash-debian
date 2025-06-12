#!/bin/bash

# 1. Создание структуры директорий
echo "1. Creating directory structure..."
sudo mkdir -p /opt/docker/dockercompose/task-13
cd /opt/docker/dockercompose || exit

# 2. Создание docker-compose.yml
echo "2. Creating docker-compose.yml..."
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile.phpmyadmin
    image: custom-phpmyadmin
    container_name: phpmyadmin
    ports:
      - "8080:80"
    networks:
      - dockercompose-frontend
    environment:
      - PMA_HOST=mydb
      - PMA_PORT=3306
    depends_on:
      mydb:
        condition: service_healthy

  mydb:
    build:
      context: .
      dockerfile: Dockerfile.mariadb
    image: custom-mariadb
    container_name: mariadb
    networks:
      - dockercompose-frontend
    volumes:
      - mysql_data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=rootpass
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-prootpass"]
      interval: 10s
      timeout: 15s
      retries: 5

networks:
  dockercompose-frontend:
    driver: bridge

volumes:
  mysql_data:
    driver: local
  backup_volume:
    driver: local
EOF

# 3. Создание Dockerfile для phpMyAdmin
echo "3. Creating Dockerfile.phpmyadmin..."
cat << 'EOF' > Dockerfile.phpmyadmin
FROM phpmyadmin/phpmyadmin:5.2.0-apache
RUN apt-get update && apt-get install -y iputils-ping && rm -rf /var/lib/apt/lists/*
EOF

# 4. Создание Dockerfile для MariaDB
echo "4. Creating Dockerfile.mariadb..."
cat << 'EOF' > Dockerfile.mariadb
FROM mariadb:10.11
RUN apt-get update && apt-get install -y iputils-ping && rm -rf /var/lib/apt/lists/*
EOF

# 5. Запуск сервисов
echo "5. Starting services with docker-compose..."
docker-compose up -d

# 6. Проверка соединения между контейнерами
echo "6. Testing network connectivity..."
docker-compose exec frontend ping -c 3 mydb
docker-compose exec mydb ping -c 3 frontend

# 7. Проверка healthcheck (сломать и починить)
echo "7. Testing healthcheck..."
docker-compose exec mydb chmod 000 /var/lib/mysql
sleep 10
docker-compose ps
docker-compose exec mydb chmod 755 /var/lib/mysql
docker-compose restart mydb
sleep 5
docker-compose ps

# 8. Создание базы данных и таблиц через phpMyAdmin (ожидание готовности MySQL)
echo "8. Waiting for MySQL to be ready..."
while ! docker-compose exec mydb mysqladmin ping -h localhost -u root -prootpass --silent; do
    sleep 5
done

echo "Creating database and tables..."
docker-compose exec mydb mysql -u root -prootpass -e "
CREATE DATABASE IF NOT EXISTS mydb;
USE mydb;
CREATE TABLE IF NOT EXISTS mytable (
  id INT AUTO_INCREMENT PRIMARY KEY,
  data TEXT,
  datamodified TIMESTAMP DEFAULT NOW()
);
INSERT INTO mytable(data) VALUES('testdata01');
INSERT INTO mytable(data) VALUES('testdata02');
INSERT INTO mytable(data) VALUES('testdata03');
"

# 9. Создание дампа базы данных
echo "9. Creating database dump..."
docker run --rm --volumes-from mariadb \
  -v /opt/docker/dockercompose/task-13:/backup \
  -v backup_volume:/tmp \
  mariadb:10.11 \
  bash -c 'mysqldump -h mydb -u root -prootpass --all-databases > /backup/mydb.sql'

# 10. Проверка дампа
echo "10. Verifying dump..."
ls -lh /opt/docker/dockercompose/task-13/mydb.sql

echo "Done! phpMyAdmin is available at http://localhost:8080 (login: root, password: rootpass)"
