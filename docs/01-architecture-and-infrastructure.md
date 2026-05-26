# 01. Архитектура и инфраструктура

Документ описывает физическую и логическую инфраструктуру проекта **Street Retail Aggregator** — агрегатора коммерческой недвижимости со скорингом помещений под бизнес арендатора.

---

## 1.1. Общая архитектура

```
┌──────────────────────┐         HTTPS (TLS-туннель)
│  Flutter APK (Android│ ───────────────────────────┐
│  /iOS/desktop)       │                            │
└──────────────────────┘                            ▼
                                  ┌────────────────────────────────┐
                                  │  cloudflared (Windows-сервис)  │
                                  │  api.magomedov.online → :8080  │
                                  └────────────────┬───────────────┘
                                                   │
                                                   ▼
                            ┌──────────────────────────────────────┐
                            │   retail-backend (Windows-сервис)    │
                            │   Spring Boot 3, JDK 21, NSSM/SYSTEM │
                            │                                      │
                            │  ┌────────────────────────────────┐  │
                            │  │ Controllers (REST + WS/STOMP)  │  │
                            │  │ Security (JWT)                 │  │
                            │  │ Services (бизнес-логика)       │  │
                            │  │ JPA Repositories               │  │
                            │  │ Caffeine (L1 cache)            │  │
                            │  └────────────────────────────────┘  │
                            └────────────┬─────────────────────────┘
                                         │
              ┌──────────────────────────┼──────────────────────────┐
              ▼                          ▼                          ▼
       ┌─────────────┐         ┌──────────────────┐        ┌──────────────────┐
       │ PostgreSQL  │         │  Overpass API    │        │   OpenRouter     │
       │ :5434       │         │  (локальный      │        │   (LLM, free)    │
       │ (Docker)    │         │  контейнер :12345│        │  meta-llama 3.3  │
       │             │         │  PBF ЦФО на D:\) │        │  qwen3, glm-4.5  │
       └─────────────┘         └──────────────────┘        └──────────────────┘
```

**Принципы:**

- **Single-host development/production.** Бэкенд работает на машине разработчика как Windows-сервис под SYSTEM, наружу публикуется через Cloudflare Tunnel. Это не «продакшн сервер», а пользовательская Windows-инсталляция — отсюда специфика деплоя (см. §1.6).
- **Stateless backend.** Все долговременные данные — в PostgreSQL и на ФС (`./uploads`). В памяти JVM — только два Caffeine-кэша с TTL 60 минут.
- **OSM-данные локальны.** Overpass API публичные mirror'ы (overpass-api.de и др.) исключены из конфига: они нестабильны и медленны. Локальный контейнер на PBF Центрального ФО отвечает за 10–500 мс.

---

## 1.2. Стек технологий

| Слой           | Технология                                                         |
|----------------|--------------------------------------------------------------------|
| Backend        | Spring Boot 3, Java 21 (Eclipse Adoptium JDK 21.0.11)              |
| Persistence    | Spring Data JPA, Hibernate 6, PostgreSQL 16                        |
| In-memory cache| Caffeine 3 (Spring `@Cacheable`)                                   |
| HTTP-клиент    | Spring `RestClient` поверх `java.net.http.HttpClient` (JDK 17+)   |
| Real-time      | Spring WebSocket + STOMP + SockJS fallback                         |
| Security       | Spring Security + JJWT (HS256, jjwt-api 0.x)                       |
| Email          | Spring Mail (SMTP gmail.com:587, STARTTLS)                         |
| Frontend       | Flutter (Dart) + MapLibre/OSM tiles                                |
| Geo-data       | OpenStreetMap через Overpass API (`wiktorn/overpass-api` Docker)   |
| LLM            | OpenRouter API (бесплатные модели каскадом)                        |
| Документация   | springdoc-openapi (Swagger UI)                                     |
| Туннелирование | Cloudflare Tunnel (`cloudflared`)                                  |
| Service manager| NSSM (Non-Sucking Service Manager) для Windows                     |

---

## 1.3. Точка входа: `BackendApplication`

[`BackendApplication.java`](../backend/src/main/java/com/example/backend/BackendApplication.java)

```java
@SpringBootApplication
@EnableScheduling
public class BackendApplication {

    public static void main(String[] args) {
        SpringApplication.run(BackendApplication.class, args);
    }

    /**
     * Регистрируем JavaTimeModule, чтобы LocalDateTime в DTO
     * сериализовались в ISO-строки, а не «массив [yyyy, m, d, h, m, s]».
     */
    @Bean
    public ObjectMapper objectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        mapper.registerModule(new JavaTimeModule());
        return mapper;
    }
}
```

**Что важно:**

- `@EnableScheduling` — нужен для cron-задачи очистки Overpass-кэша (`OverpassPersistentCache.cleanupExpired`, ежедневно в 03:00).
- Кастомный `ObjectMapper` с `JavaTimeModule` обязателен: используется и для HTTP-сериализации DTO, и для записи `OverpassAreaSnapshot`/`ScoredPropertyDto` в JSON-колонки `overpass_cache.response_json` и `property_score_snapshots.payload_json`. Без него `LocalDateTime` пишется как массив чисел.

---

## 1.4. Конфигурация: `application.properties`

[`application.properties`](../backend/src/main/resources/application.properties)

Все параметры читаются с дефолтами и могут быть переопределены через переменные окружения (формат `${ENV_VAR:default}`).

### База данных

```properties
spring.datasource.url=${SPRING_DATASOURCE_URL:jdbc:postgresql://127.0.0.1:5434/retail_aggregator?sslmode=disable}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME:myuser}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD:mypassword}
spring.jpa.hibernate.ddl-auto=${SPRING_JPA_DDL_AUTO:update}
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
```

- **Порт 5434** — это не дефолтный 5432 PostgreSQL; так маппится `docker-compose.dev.yml`, чтобы не конфликтовать с возможным локальным PostgreSQL.
- **`ddl-auto=update`** — Hibernate сам добавляет недостающие таблицы/колонки. Подходит для текущего этапа разработки; на production-инсталляции стоит мигрировать на Flyway/Liquibase, но пока это вне scope.

### Overpass API

```properties
overpass.api.urls=${OVERPASS_API_URLS:http://localhost:12345/api/interpreter}
overpass.api.url=${OVERPASS_API_URL:http://localhost:12345/api/interpreter}
overpass.cache.ttl-hours=${OVERPASS_CACHE_TTL_HOURS:168}
```

- **`overpass.api.urls`** — CSV-список mirror'ов. Сервис [`OverpassPlacesService`](../backend/src/main/java/com/example/backend/service/OverpassPlacesService.java) пробует их по порядку с retry и exp-backoff (см. §4 «Сервисы»).
- **Публичные mirror'ы исключены намеренно**. Они медленные, нестабильные и портят UX. Локальный контейнер отвечает за 10–500 мс, и FAILED-статус при его падении лучше, чем 30-секундное ожидание публичного зеркала.
- **TTL 168 часов (7 дней)** — для постоянного кэша в PostgreSQL. OSM-данные меняются медленно: новый ТЦ или станция метро — события месяца.

### Скоринг

```properties
property.score.snapshot.ttl-hours=${PROPERTY_SCORE_TTL_HOURS:24}
```

- Снэпшоты оценки помещений в БД хранятся 24 часа. Открытие карточки/списка повторно в этот период не пересчитывает скоринг и не делает Overpass-вызовов.
- Параметр `force=true` в API обходит TTL — для кнопки «обновить оценку» на фронте.

### LLM (OpenRouter)

```properties
openrouter.api.key=${OPENROUTER_API_KEY:}
```

Используется для AI-объяснения скоринга на естественном языке (см. [`OpenRouterAiService`](../backend/src/main/java/com/example/backend/service/OpenRouterAiService.java), §4.8).

### Файловое хранилище и почта

```properties
app.upload.dir=${APP_UPLOAD_DIR:./uploads}
spring.servlet.multipart.max-file-size=10MB
spring.servlet.multipart.max-request-size=60MB

spring.mail.host=${MAIL_HOST:smtp.gmail.com}
spring.mail.port=${MAIL_PORT:587}
spring.mail.properties.mail.smtp.auth=true
spring.mail.properties.mail.smtp.starttls.enable=true
```

- Картинки помещений и аватары — на локальной ФС (`./uploads`), отдаются Spring через `/uploads/**` (см. `WebMvcConfig`).
- SMTP-режим: STARTTLS на 587 порту (Gmail). Используется для отправки 6-значного кода верификации email.

---

## 1.5. Docker dev-окружение

[`docker-compose.dev.yml`](../docker-compose.dev.yml) — overlay поверх основного `docker-compose.yml` (который содержит nginx/certbot/backend для условного production).

### Что поднимает dev-overlay

```yaml
services:
  db:
    ports:
      - "5434:5432"          # Проброс порта на хост — Spring подключается с localhost

  backend:
    profiles: ["never"]      # В dev backend запускается вне Docker

  nginx:
    profiles: ["never"]
  certbot:
    profiles: ["never"]

  overpass:
    image: wiktorn/overpass-api
    container_name: overpass_local
    restart: always
    ports:
      - "12345:80"
    volumes:
      - D:\overpass_db:/db   # PBF ЦФО ~40ГБ → на D:\, чтобы не съесть системный диск
    environment:
      OVERPASS_PLANET_URL: "http://download.geofabrik.de/russia/central-fed-district-latest.osm.pbf"
      OVERPASS_PLANET_PREPROCESS: "osmium cat /db/planet.osm.bz2 --input-format=osm.pbf -o /db/planet.tmp.bz2 --output-format=osm.bz2 --overwrite && mv -f /db/planet.tmp.bz2 /db/planet.osm.bz2"
      OVERPASS_MAX_TIMEOUT: "1000"
      OVERPASS_MODE: init
      OVERPASS_META: "yes"
      OVERPASS_USE_AREAS: "no"
```

### Особенности конфига Overpass-контейнера

1. **PBF вместо BZ2.** Geofabrik для большинства суб-регионов уже не отдаёт `.osm.bz2`, только `.osm.pbf`. Поэтому `OVERPASS_PLANET_PREPROCESS` конвертирует PBF в BZ2 через `osmium` on-the-fly. Чтение идёт явно с `--input-format`, потом атомарный `mv` — это обход проблемы 9P/virtiofs sync на Docker Desktop Windows.
2. **`OVERPASS_MAX_TIMEOUT: 1000`** — серверный лимит выполнения запроса в секундах. Достаточно с запасом для тяжёлых `nwr[...]` запросов в плотных кварталах Москвы.
3. **`OVERPASS_USE_AREAS: no`** — отключена тяжёлая переиндексация областей. Скоринг использует только `around:` queries, `area:` не нужны.
4. **Первый запуск — 20–30 минут** на импорт PBF. Дальше контейнер держит индекс на диске и стартует быстро.

### Команды поднятия

```powershell
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d db
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d overpass
```

---

## 1.6. Деплой backend как Windows-сервис

Хост — Windows-машина пользователя. Backend разворачивается как **`retail-backend`** через **NSSM** (Non-Sucking Service Manager). Скрипт установки — `install-services.ps1`.

### Жизненный цикл сервиса

| Действие             | Команда                                              | Кто выполняет       |
|----------------------|------------------------------------------------------|---------------------|
| Сборка JAR           | `gradlew bootJar`                                    | Можно без админа    |
| Запуск/остановка     | `Start-Service retail-backend` / `Stop-Service ...`  | **Только админ**    |
| Перезапуск           | `Restart-Service retail-backend -Force`              | **Только админ**    |
| Проверка живости     | `Invoke-WebRequest https://api.magomedov.online/api/properties/2 -UseBasicParsing` | Можно без админа |
| Логи stdout          | `backend/logs/stdout.log`                            | Чтение из репо      |
| Логи stderr          | `backend/logs/stderr.log`                            | Чтение из репо      |

**Важная особенность.** Сервис работает от SYSTEM, поэтому обычный non-admin PowerShell получает Access denied при попытке управлять им. `Start-Process -Verb RunAs` с UAC-elevation тоже не отрабатывает чисто. Правильный рабочий процесс:

1. Изменения в коде.
2. `./gradlew.bat bootJar` — собрать JAR (без админа).
3. Пользователь в админ-PowerShell: `Restart-Service retail-backend -Force`.
4. Проверка: `Invoke-WebRequest https://api.magomedov.online/api/properties/2`.

### Cloudflare Tunnel

`cloudflared` — отдельный Windows-сервис, проксирует **`https://api.magomedov.online`** → **`localhost:8080`**. Бесплатный TLS-эндпоинт, доступный с мобильного устройства без локальной сети. Конфиг — стандартный `cloudflared tunnel`, токен в системном `cloudflared/config.yml`.

### Сборка Flutter

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.magomedov.online
```

`--dart-define` подставляет URL в `frontend/lib/src/config/api_config.dart`, чтобы прод-APK ходил не на `10.0.2.2:8080` (эмулятор), а на туннель.

### Локации инструментов

- JDK: `C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot`
- Flutter: `C:\Users\User\flutter\bin\flutter.bat`

---

## 1.7. Конфигурации Spring: подробный разбор

### 1.7.1. `CacheConfig` — Caffeine L1-кэш

[`CacheConfig.java`](../backend/src/main/java/com/example/backend/config/CacheConfig.java)

```java
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public CacheManager cacheManager() {
        CaffeineCacheManager manager = new CaffeineCacheManager("overpassArea", "propertyScore");
        manager.setCaffeine(Caffeine.newBuilder()
                .expireAfterWrite(60, TimeUnit.MINUTES)
                .maximumSize(2000));
        return manager;
    }
}
```

**Два именованных кэша:**

| Имя             | Что хранит                                                              |
|-----------------|-------------------------------------------------------------------------|
| `overpassArea`  | `OverpassAreaSnapshot` — POI + транспорт вокруг точки                  |
| `propertyScore` | `ScoredPropertyDto` — короткоживущий кэш внутри одного батча           |

**Параметры:**

- `expireAfterWrite(60 min)` — типичные точки переоткрываются за минуты, час — компромисс между свежестью и hit-rate.
- `maximumSize(2000)` — для плотного центра Москвы ~1500 уникальных точек×радиусов, с запасом.

**Двухуровневый кэш.** Caffeine — это L1 (микросекунды, per-JVM). L2 — PostgreSQL-таблица `overpass_cache` (см. §3 «Domain Model» и `OverpassPersistentCache`). После рестарта backend Caffeine пуст, и без L2 первый запрос на каждую точку бил бы по Overpass даже на «горячий» адрес.

---

### 1.7.2. `RestClientConfig` — HTTP-клиенты для внешних API

[`RestClientConfig.java`](../backend/src/main/java/com/example/backend/config/RestClientConfig.java)

Под капотом — `java.net.http.HttpClient` (JDK 17+). Это даёт persistent-соединения, HTTP/2-мультиплексирование и переиспользование TLS-сессий. На старом `SimpleClientHttpRequestFactory` каждое HTTP-обращение к Overpass делало полный TCP+TLS handshake; для батча из 20 помещений × 1 запрос на каждое — 20+ handshake'ов. После миграции — один пул, переживающий весь батч.

```java
@Bean
public RestClient overpassRestClient() {
    HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .version(HttpClient.Version.HTTP_2)
            .executor(Executors.newFixedThreadPool(16, r -> {
                Thread t = new Thread(r, "overpass-http");
                t.setDaemon(true);
                return t;
            }))
            .build();
    JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(http);
    factory.setReadTimeout(Duration.ofSeconds(30));
    return RestClient.builder()
            .requestFactory(factory)
            .build();
}
```

**Параметры:**

- `connectTimeout(5s)` — TCP-connect. Локальный Overpass отвечает мгновенно; 5с — запас на холодный кэш ARP/DNS.
- `readTimeout(30s)` — Overpass под нагрузкой штатно отвечает 10–25с. Резать жёстче нельзя, иначе возвращает пустое тело и скоринг получит нули конкурентов.
- Пул из **16 потоков** покрывает 8 параллельных скоринг-нитей × 1 запрос на помещение, с запасом на ретраи (см. `PropertyScoringService.scoreAndRankProperties` использует `ForkJoinPool(8)`).
- HTTP/2 — Overpass поддерживает.

**Второй клиент для OpenRouter:**

```java
@Bean
public RestClient openRouterRestClient(@Value("${openrouter.api.key}") String apiKey) {
    HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .version(HttpClient.Version.HTTP_2)
            .build();
    JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(http);
    factory.setReadTimeout(Duration.ofSeconds(60));
    return RestClient.builder()
            .requestFactory(factory)
            .baseUrl("https://openrouter.ai/api/v1")
            .defaultHeader("Authorization", "Bearer " + apiKey)
            .build();
}
```

- `readTimeout(60s)` — DeepSeek/Llama free-tier на OpenRouter иногда стоят в очереди.
- Авторизация через `Bearer` в дефолтном заголовке: все запросы автоматически авторизованы.

---

### 1.7.3. `WebSocketConfig` — STOMP-брокер для чата

[`WebSocketConfig.java`](../backend/src/main/java/com/example/backend/config/WebSocketConfig.java)

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic");
        config.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*").withSockJS();
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*");
    }
}
```

- **Endpoint `/ws`** — двойная регистрация: и с SockJS-fallback (для браузеров без WebSocket), и без (для нативного Flutter-клиента, который использует `stomp_dart_client`).
- **`/topic`** — outgoing-канал брокера (сервер → клиенты).
- **`/app`** — incoming-префикс (клиенты → @MessageMapping в `ChatController`).
- **`setAllowedOriginPatterns("*")`** — открытый CORS. Дублирует разрешение `/ws/**` в `SecurityConfig` (см. §2 «Security»).

В runtime используется в [`ChatController`](../backend/src/main/java/com/example/backend/controller/ChatController.java) для реал-тайм доставки сообщений (см. §4 «Сервисы»).

---

### 1.7.4. `WebMvcConfig` — раздача файлов

[`WebMvcConfig.java`](../backend/src/main/java/com/example/backend/config/WebMvcConfig.java)

```java
@Override
public void addResourceHandlers(ResourceHandlerRegistry registry) {
    String location = fileStorageService.getRoot().toUri().toString();
    registry.addResourceHandler("/uploads/**")
            .addResourceLocations(location)
            .setCachePeriod(3600);
}
```

- `/uploads/**` → корневой каталог `app.upload.dir` (по умолчанию `./uploads`).
- `Cache-Control: max-age=3600` — клиент кэширует картинки на час. Имена файлов — UUID (см. `FileStorageService`), коллизий нет, инвалидация не нужна.
- Доступ публичный (в `SecurityConfig`: `requestMatchers("/uploads/**").permitAll()`).

---

### 1.7.5. `DataInitializer` — справочник категорий бизнеса

[`DataInitializer.java`](../backend/src/main/java/com/example/backend/config/DataInitializer.java)

`CommandLineRunner` с `@Order(1)` — выполняется один раз на старте приложения, идемпотентно (`findOrCreate`).

**Что делает:** заполняет таблицу `business_categories` иерархией: корневая категория → подкатегории, каждой подкатегории присваивается CSV OSM-тегов.

Пример:

```java
BusinessCategory food = findOrCreate("Еда и напитки", null, null);

findOrCreate("Продуктовый магазин", food,
        "shop=supermarket,shop=convenience,shop=grocery,shop=greengrocer,shop=general");
findOrCreate("Кофейня", food,
        "amenity=cafe,shop=coffee");
findOrCreate("Аптека", beauty,
        "amenity=pharmacy,healthcare=pharmacy,shop=chemist");
```

**Полная иерархия (на момент v2.0):**

| Корневая категория       | Подкатегорий |
|--------------------------|--------------|
| Еда и напитки            | 8            |
| Красота и здоровье       | 7            |
| Товары                   | 7            |
| Сервис и услуги          | 5            |
| Образование и развитие   | 3            |

Итого: **5 корневых + 30 листовых = 35 категорий**.

**Зачем OSM-теги.** В [`PropertyScoringService`](../backend/src/main/java/com/example/backend/service/PropertyScoringService.java) строится индекс `tag → List<BusinessCategory>`, по которому результаты Overpass-запроса сматчиваются на «прямого конкурента» (тег категории арендатора) и «синергичного соседа» (тег из `desiredNeighbors`). Источник тегов — официальная Wiki OSM, в России теги ставятся аккуратно: pharmacy/cafe/restaurant и т.д. почти всегда совпадают с реальным типом заведения.

**Идемпотентность:**

```java
private BusinessCategory findOrCreate(String name, BusinessCategory parent, String osmTags) {
    BusinessCategory category = categoryRepository.findByName(name).orElseGet(() -> {
        BusinessCategory newCat = BusinessCategory.builder()
                .name(name)
                .parentCategory(parent)
                .build();
        return categoryRepository.save(newCat);
    });

    boolean changed = false;
    if (osmTags != null && !osmTags.equals(category.getOsmTags())) {
        category.setOsmTags(osmTags);
        changed = true;
    }
    if (parent != null && category.getParentCategory() == null) {
        category.setParentCategory(parent);
        changed = true;
    }
    if (changed) {
        categoryRepository.save(category);
    }
    return category;
}
```

При повторном запуске:
- Если категория уже есть и теги/parent те же — ничего не делает.
- Если теги изменились (например, добавили новый OSM-shop в маппинг) — обновляет колонку `search_keywords`.
- Если parent был null (например, ручная вставка через админку) и теперь задан — выставляет.

---

## 1.8. Кэширование: трёхуровневая схема

| Уровень | Хранилище              | TTL      | Класс                          | Назначение                                       |
|---------|------------------------|----------|--------------------------------|--------------------------------------------------|
| **L1**  | Caffeine (in-memory)   | 60 мин   | `CacheConfig` `overpassArea`   | Микросекундный доступ внутри одной JVM-сессии   |
| **L2**  | PostgreSQL `overpass_cache` | 7 дней | `OverpassPersistentCache`     | Переживает рестарт backend; общий для всех ядер |
| **L3**  | PostgreSQL `property_score_snapshots` | 24 часа | `PropertyScoreSnapshotService` | Готовые DTO скоринга — пропуск Overpass-цикла |

Поток запроса при открытии карточки помещения арендатором:

```
1. PropertyController.getProperty(id)
   └→ PropertyService.scorePropertyForTenant
      └→ PropertyScoreSnapshotService.scoreWithSnapshot
         ├─ L3 HIT?  → возврат ScoredPropertyDto из БД (~10мс)
         └─ L3 MISS  → PropertyScoringService.scorePropertyWithGis
                       └→ OverpassPlacesService.searchAreaSnapshot
                          ├─ L1 HIT?  → возврат OverpassAreaSnapshot (~50μs)
                          ├─ L2 HIT?  → возврат + промоут в L1 (~3мс)
                          └─ L2 MISS  → HTTP к Overpass + запись в L2 (~500мс…10с)
```

Подробнее каждый слой — в §3 «Domain Model» (структура таблиц кэшей) и §4 «Сервисы» (логика L2/L3).

---

## 1.9. Логирование и наблюдаемость

- **Логи stdout/stderr** — `backend/logs/stdout.log`, `backend/logs/stderr.log` (NSSM перенаправляет потоки сервиса в файлы).
- **Spring Security** — уровень настраивается через `LOG_LEVEL_SECURITY` (по умолчанию INFO).
- **Бизнес-логи** — на уровне INFO/DEBUG в сервисах. Маркеры: `[OVERPASS]`, `[OVERPASS-PCACHE]`, `[SCORE-SNAP]`, `[COMP-CTX]`, `[COMP-SCORE]`, `[COMP-EMPTY]`, `[COMP-NO-MATCH]`, `[SYNERGY]`, `[TRANSPORT]`, `[AI]`, `[PUSH NOTIFICATION]`. Это сделано для grep-ability в больших логах при дебаге скоринга.
- **Health-check** — отдельного `/actuator/health` нет; в качестве liveness используется `GET /api/properties/2` (публичный endpoint), ожидается HTTP 200.

---

## 1.10. Зависимости между компонентами при старте

```
DataSource (Postgres)
    │
    ▼
EntityManagerFactory, Hibernate (ddl-auto=update создаёт/мигрирует схему)
    │
    ▼
JpaRepositories
    │
    ▼
CacheManager (Caffeine)         RestClient'ы (HTTP/2 пулы)
    │                                  │
    └──────────────┬───────────────────┘
                   ▼
            Сервисы (Property, Scoring, Auth, ...)
                   │
                   ▼
            DataInitializer (CommandLineRunner @Order(1))
                   │
                   ▼
            Контроллеры доступны
                   │
                   ▼
            ApplicationReadyEvent
                   │
                   ▼
            PropertyScoreSnapshotService.cleanupOnStartup()
            — удаление snapshot'ов старых версий алгоритма
```

`@Scheduled(cron = "0 0 3 * * *")` в `OverpassPersistentCache.cleanupExpired` запускается отдельно по расписанию (раз в сутки в 3:00) и удаляет записи старше TTL из `overpass_cache`.

---

## 1.11. Известные ограничения и trade-off'ы

1. **`ddl-auto=update`** — Hibernate мигрирует схему сам. Хорошо для скорости разработки, плохо для аудита изменений и rollback. Миграция на Flyway/Liquibase — будущий шаг.
2. **Single-host деплой.** Backend, Postgres, Overpass, файловое хранилище — всё на одной Windows-машине. Нет горизонтального масштабирования. Каффеин-кэш не распределён (что не критично, потому что L2 в Postgres покрывает рестарт).
3. **Публичные mirror'ы Overpass отключены.** Если локальный контейнер упадёт — fallback на public нет. Trade-off в пользу скорости и предсказуемости (FAILED-статус, у скоринга есть корректная обработка).
4. **Bearer-токен JWT 24 часа без refresh.** После истечения нужен повторный логин. Мульти-аккаунт во Flutter (`AuthService.getSavedAccounts`) частично смягчает.
5. **`NotificationService` — заглушка.** Реального FCM нет, push-уведомления только пишутся в лог. Подробнее — §4 «Сервисы».
6. **Overpass-снимок ЦФО.** PBF загружается с Geofabrik для Центрального ФО (~600МБ→~40ГБ в индексе). Для адресов вне ЦФО локальный Overpass вернёт пусто (что корректно отработается как `OVERPASS_UNAVAILABLE` если включится fallback на упавшие public mirror'ы, либо как «вокруг ничего нет» — баг).
