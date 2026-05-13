# Инструкция по деплою

> Если приложение уже задеплоено и нужно только накатить новую версию — иди сразу в [раздел 10](#10-обновление-кода-в-проде).

## 1. Подготовка домена (в кабинете reg.ru)

Домен `magomedov.online` уже занят сайтом-визиткой (GitHub Pages) — трогать не нужно.
Для бэкенда добавляем поддомен `api.magomedov.online`:

1. Личный кабинет reg.ru → твой домен → **Управление DNS**.
2. Добавить **A-запись**:
   - Subdomain: `api`
   - Тип: `A`
   - Значение: `IP_твоего_VPS` (например `185.12.34.56`)
   - TTL: 3600
3. Дождаться распространения (обычно 10–30 мин, иногда до часа). Проверка:
   ```
   nslookup api.magomedov.online
   ```
   должна вернуть IP сервера.

Сайт-визитка по `magomedov.online` продолжит работать с GitHub Pages — это отдельные DNS-записи.

## 2. Аренда VPS

Подойдёт любой: Timeweb Cloud, Beget, Selectel, REG.ru VPS.
Минимум: **2 GB RAM, 2 vCPU, 20 GB SSD, Ubuntu 22.04**.

После оплаты получишь IP и root-пароль.

## 3. Первичная настройка сервера

Подключаемся по SSH:
```bash
ssh root@IP_СЕРВЕРА
```

Ставим Docker:
```bash
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
```

Открываем порты в фаерволе (если используется ufw):
```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

## 4. Заливка проекта

Вариант через git (рекомендуется):
```bash
cd /opt
git clone https://github.com/ТВОЙ_ЛОГИН/street-retail-aggregator.git
cd street-retail-aggregator
```

Или через scp с локальной машины (PowerShell):
```powershell
scp -r c:\Games\street-retail-aggregator root@IP_СЕРВЕРА:/opt/
```

## 5. Создание `.env`

На сервере:
```bash
cp .env.example .env
nano .env
```

Заполни все значения. Сгенерируй сложный пароль для БД:
```bash
openssl rand -base64 32
```

Минимальный набор переменных на текущий момент:
```
POSTGRES_DB=retail_aggregator
POSTGRES_USER=...
POSTGRES_PASSWORD=...
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=...
MAIL_PASSWORD=...
OPENROUTER_API_KEY=...
# Опционально:
# OVERPASS_API_URL=https://overpass-api.de/api/interpreter
# APP_UPLOAD_DIR=/app/uploads
```
`TWOGIS_API_KEY` больше не используется — поиск соседних бизнесов перешёл на Overpass (OpenStreetMap, без ключа).

## 6. Первый запуск (HTTP, без SSL)

```bash
docker compose up -d --build
```

Проверь, что бэкенд отвечает:
```bash
curl http://api.magomedov.online/
```

Если получил ответ от Spring Boot (даже 404) — связка работает.

## 7. Получение SSL-сертификата Let's Encrypt

```bash
docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d api.magomedov.online \
  --email твой@email.ru \
  --agree-tos --no-eff-email
```

Должно вывести `Successfully received certificate`.

## 8. Включение HTTPS

Открой `nginx/conf.d/api.conf`:
- Раскомментируй блок `server { listen 443 ssl; ... }`.
- В блоке `listen 80` раскомментируй `return 301 https://$host$request_uri;` и удали временный `location / { proxy_pass ... }` (оставь только `location /.well-known/acme-challenge/`).

Перезапусти Nginx:
```bash
docker compose restart nginx
```

Проверь:
```bash
curl https://api.magomedov.online/
```

Сертификат будет автоматически обновляться сервисом `certbot` (каждые 12 часов проверка).

## 9. Сборка Flutter-приложения с прод-URL

На локальной машине, в папке `frontend`:

**Android (APK для распространения):**
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.magomedov.online
```
APK будет в `build/app/outputs/flutter-apk/app-release.apk`.

**Android App Bundle (для Google Play):**
```bash
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.magomedov.online
```

**iOS:**
```bash
flutter build ios --release --dart-define=API_BASE_URL=https://api.magomedov.online
```

**Запуск для теста на устройстве:**
```bash
flutter run --release --dart-define=API_BASE_URL=https://api.magomedov.online
```

Без `--dart-define` приложение продолжит ходить на `10.0.2.2:8080` (для локальной разработки на эмуляторе).

## 10. Обновление кода в проде

### 10.1. Если поменялся только код (без `.env`, без новых volume)

На локальной машине:
```bash
git add -A
git commit -m "описание изменений"
git push origin main
```

На сервере:
```bash
cd /opt/street-retail-aggregator
git pull
docker compose up -d --build backend
docker compose logs -f backend   # Ctrl+C когда увидишь "Started ... in N seconds"
```

### 10.2. Если поменялся `.env`

`.env` в гите не лежит (см. `.gitignore`), поэтому правки делаются прямо на сервере:

```bash
cd /opt/street-retail-aggregator
git pull
nano .env                        # внеси новые значения (или scp'ом залей с локала)
docker compose up -d --build backend
docker compose logs -f backend
```

Если меняются переменные, которые читает не только backend (например, `POSTGRES_*`), переподними и базу:
```bash
docker compose up -d --build       # без указания сервиса = пересоздать все, у кого env поменялся
```
ВНИМАНИЕ: смена `POSTGRES_PASSWORD` после первой инициализации НЕ перезапишет пароль внутри Postgres-volume. Меняй пароль через `ALTER USER` в psql, не через `.env`.

### 10.3. Если появился новый volume (например, для `uploads/`)

В этом релизе добавился аплоад фото помещений и аватарок. Файлы пишутся в `./uploads` внутри контейнера backend. Без volume они исчезнут при следующем `--build backend`.

Открой `docker-compose.yml` и в сервис `backend` добавь:
```yaml
    volumes:
      - ./uploads:/app/uploads
```
(сразу под `environment:` блоком, на том же уровне отступа).

И в `nginx/conf.d/api.conf` в HTTPS-блок добавь раздачу статики (чтобы клиенты могли скачивать картинки):
```nginx
    client_max_body_size 25M;

    location /uploads/ {
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
    }
```
(если не хочешь гонять статику через Spring — можно прокинуть `./uploads` в nginx и раздавать напрямую, но это опционально).

Затем:
```bash
mkdir -p /opt/street-retail-aggregator/uploads
docker compose up -d --build backend
docker compose restart nginx
```

### 10.4. Откат, если что-то пошло не так

```bash
git log --oneline -10            # найди хеш предыдущего рабочего коммита
git checkout <hash>
docker compose up -d --build backend
```
Чтобы вернуться к актуальной ветке: `git checkout main && git pull`.

## Полезные команды

```bash
# Логи всех сервисов
docker compose logs -f

# Логи только бэкенда
docker compose logs -f backend

# Остановить всё
docker compose down

# Полностью удалить данные БД (ОСТОРОЖНО)
docker compose down -v
```

## Известные нюансы

- **Сохранность БД**: данные в volume `pgdata`. `docker compose down` их НЕ удаляет, удаляет только `down -v`. Делай регулярные бэкапы:
  ```bash
  docker exec retail_db pg_dump -U $POSTGRES_USER $POSTGRES_DB > backup_$(date +%F).sql
  ```
- **Старые секреты в git-истории**: Gmail-пароль, 2GIS и OpenRouter ключи раньше лежали в `application.properties`. После публикации репозитория **отозви их и выпусти новые** — старые остались в истории коммитов.
- **БД больше не торчит наружу**: убран `ports: 5434:5432`. Подключиться извне теперь нельзя (это правильно). Локальная разработка на хосте по-прежнему работает через `localhost:5434`, если поднимешь dev-compose с пробросом порта.
