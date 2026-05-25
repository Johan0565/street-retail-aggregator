# Локальный Overpass API

Гайд по работе с локальным контейнером Overpass для street-retail-aggregator.

## Что это и зачем

`overpass_local` — Docker-контейнер с собственной копией OSM-данных
**Центрального федерального округа** (Москва, МО, Тула, Калуга и т.д.,
17 регионов). Snapshot OSM зафиксирован на дату первого импорта и
автоматически не обновляется.

Заменяет публичные mirror'ы `overpass-api.de`, `kumi.systems`,
`private.coffee`. Преимущества:

- Без HTTP 429 / rate limit
- Запрос отрабатывает за ~10–50мс вместо 10–60с
- Можно бомбить тысячи запросов параллельно
- Не зависит от доступности интернета и публичных серверов

Backend ([OverpassPlacesService](../backend/src/main/java/com/example/backend/service/OverpassPlacesService.java))
читает список mirror'ов из `overpass.api.urls`. По умолчанию первым стоит
`http://localhost:12345/api/interpreter`, дальше идут публичные mirror'ы
как fallback на случай, если контейнер не запущен.

## Управление контейнером

Все команды — из корня проекта (`C:\Games\street-retail-aggregator`).

### Запуск

```powershell
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d overpass
```

### Остановка (контейнер остаётся, данные сохраняются)

```powershell
docker stop overpass_local
```

### Запуск после стопа

```powershell
docker start overpass_local
```

### Статус

```powershell
docker ps --filter "name=overpass_local"
```

Ждём `Up X minutes (healthy)`. Если `health: starting` дольше 30 минут
после первого запуска — что-то пошло не так, см. раздел «Если что-то
сломалось».

### Логи

```powershell
docker logs --tail 50 overpass_local
```

Или с фильтром (без curl-прогрессбара):

```powershell
docker logs overpass_local 2>&1 | Select-String -Pattern "Initializing|preprocess|Failed|Database|Updating|dispatcher" -CaseSensitive:$false
```

### ⚠️ НЕ удалять контейнер

```powershell
docker rm overpass_local   # ← НЕ ДЕЛАЙ ЭТОГО
```

База в 8 ГБ лежит в overlay-слое контейнера, не в bind-mount на D:
(bind-mount слетел во время первого запуска). При `docker rm` данные
теряются — придётся 9+ часов повторно качать и импортировать.

## Использование

### Через браузер

Открой **http://localhost:12345** — там стандартный веб-UI Overpass:
поле для QL-запроса и кнопка «Run».

### Через curl/PowerShell

`POST http://localhost:12345/api/interpreter` с телом `data=<query>` в
формате `application/x-www-form-urlencoded`.

```powershell
$body = 'data=[out:json];nwr[amenity=pharmacy](around:500,55.7558,37.6176);out tags;'
Invoke-RestMethod -Uri 'http://localhost:12345/api/interpreter' -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded' | ConvertTo-Json -Depth 10
```

### Через Postman / Insomnia

- Method: `POST`
- URL: `http://localhost:12345/api/interpreter`
- Body (x-www-form-urlencoded): `data` = твой QL-запрос

## Примеры запросов

### Все Wildberries в Москве

```overpass
[out:json][timeout:60];
area[name="Москва"][admin_level=4]->.moscow;
node[brand="Wildberries"](area.moscow);
out tags;
```

### Аптеки в радиусе 1 км от Кремля

```overpass
[out:json];
nwr[amenity=pharmacy](around:1000,55.7520,37.6175);
out tags center;
```

### Все остановки общественного транспорта вокруг точки

```overpass
[out:json][timeout:25];
(
  nwr[railway=station][name](around:600,55.7558,37.6176);
  nwr[railway=subway_entrance][name](around:600,55.7558,37.6176);
  nwr[railway=tram_stop](around:600,55.7558,37.6176);
  nwr[highway=bus_stop](around:600,55.7558,37.6176);
);
out tags center;
```

### То, что делает scoring backend

```overpass
[out:json][timeout:25];
(
  nwr[shop](around:600,55.7558,37.6176);
  nwr[amenity~"^(pharmacy|cafe|restaurant|fast_food|bar|bank|atm)$"](around:600,55.7558,37.6176);
  nwr[office~"^(travel_agent|estate_agent|company|insurance)$"](around:600,55.7558,37.6176);
  nwr[healthcare~"^(clinic|doctor|pharmacy|dentist)$"](around:600,55.7558,37.6176);
);
out tags center 3500;
```

## Overpass QL шпаргалка

- `[out:json]` — формат ответа (JSON)
- `[timeout:25]` — таймаут на сервере (сек)
- `node`, `way`, `relation`, `nwr` (всё сразу) — типы OSM-объектов
- `[key=value]` — фильтр по тегу
- `[key~"^(a|b|c)$"]` — фильтр по регулярному выражению
- `(around:радиусМетров, lat, lon)` — поиск в круге
- `(юг, запад, север, восток)` — поиск в bbox
- `area[name="Москва"]` — поиск в полигоне (через `(area)`)
- `out tags` — вернуть только теги, без геометрии
- `out tags center` — теги + центр геометрии (для ways/relations)
- `out tags center 3500` — то же + hard-cap 3500 элементов

Полная документация: https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL

## Свежесть данных

Snapshot OSM зафиксирован на дату первого импорта (см. поле
`timestamp_osm_base` в любом ответе API). Контейнер настроен на init-mode,
автоматические diff-обновления **не подключены**.

Чтобы обновить до свежего среза OSM, нужно полностью переимпортировать
(см. раздел «Полный реимпорт»).

## Конфигурация

[docker-compose.dev.yml](../docker-compose.dev.yml) — сервис `overpass`:

- `OVERPASS_PLANET_URL` — URL PBF с Geofabrik (текущий: ЦФО)
- `OVERPASS_PLANET_PREPROCESS` — конвертация PBF → bz2 через osmium
- `OVERPASS_MODE=init` — импорт при первом запуске
- `OVERPASS_USE_AREAS=no` — отключаем переиндексацию областей
  (для скоринга через `around:` не нужно)
- `OVERPASS_META=yes` — включаем мета-теги (timestamp, version)
- `OVERPASS_MAX_TIMEOUT=1000` — макс. серверный таймаут на запрос

[application.properties](../backend/src/main/resources/application.properties):

```properties
overpass.api.urls=${OVERPASS_API_URLS:http://localhost:12345/api/interpreter,https://overpass-api.de/api/interpreter,...}
```

На проде эту переменную нужно переопределить только публичными mirror'ами
(локального там нет).

## Если что-то сломалось

### Контейнер не отвечает

```powershell
docker logs --tail 100 overpass_local
docker exec overpass_local sh -c "ls /db; cat /db/init_done 2>&1"
```

Если `init_done` есть — база готова, проблема в supervisord/nginx.
Перезапусти контейнер: `docker restart overpass_local`.

### Backend не видит локальный mirror

Проверь, что после старта Spring Boot в логах есть:

```
[OVERPASS] Сконфигурированы mirror'ы: [http://localhost:12345/api/interpreter, ...]
```

Если localhost не первым — проверь env-переменную `OVERPASS_API_URLS`
(возможно, переопределена в NSSM-конфиге сервиса).

Прогрев L1-кэша занимает несколько запросов. Старые ответы из L2 (PostgreSQL,
`OverpassPersistentCache`) остаются — их TTL 7 дней. Если хочешь
гарантированно использовать локальный — очисти L2:

```sql
DELETE FROM overpass_cache_entry;
```

### Полный реимпорт (если нужны свежие данные)

⚠️ Снова 9+ часов на скачку + конвертацию + импорт.

```powershell
docker stop overpass_local
docker rm overpass_local
# Если bind-mount починили в Docker Desktop → удалить и D:\overpass_db
# Иначе данные в overlay-слое, контейнер удалён = данные удалены автоматом
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d overpass
```

## Что НЕ покрыто этим Overpass'ом

- Регионы вне ЦФО (СПб, Урал, Сибирь и т.д.) — нет в snapshot
- Свежие OSM-правки после даты импорта
- Routing / маршрутизация (это другой сервис — OSRM, GraphHopper)
- Геокодирование адресов в координаты (это Nominatim)
