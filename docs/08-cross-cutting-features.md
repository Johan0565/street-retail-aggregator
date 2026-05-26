# 08. Сквозные / «фичевые» темы

Документ описывает функциональные «вертикали» проекта — то, что охватывает и backend, и frontend, и инфраструктуру. Каждая фича — это связанный набор компонентов, который имеет смысл рассматривать как единое целое.

---

## 8.1. Скоринг помещений — главная фишка проекта

**Что делает:** для каждого помещения и активного профиля поиска арендатора рассчитывает оценку **0–100 баллов** по 5 компонентам и возвращает её с человекочитаемым лейблом и цветным маркером.

### Где живёт

| Слой              | Файл                                                                                                |
|-------------------|-----------------------------------------------------------------------------------------------------|
| Алгоритм          | [`PropertyScoringService`](../backend/src/main/java/com/example/backend/service/PropertyScoringService.java) |
| Кэш L3            | [`PropertyScoreSnapshotService`](../backend/src/main/java/com/example/backend/service/PropertyScoreSnapshotService.java) |
| Источник данных   | [`OverpassPlacesService`](../backend/src/main/java/com/example/backend/service/OverpassPlacesService.java)   |
| AI-объяснение     | [`OpenRouterAiService`](../backend/src/main/java/com/example/backend/service/OpenRouterAiService.java)       |
| DTO               | [`ScoredPropertyDto`](../backend/src/main/java/com/example/backend/dto/ScoredPropertyDto.java), [`ScoreBreakdown`](../backend/src/main/java/com/example/backend/dto/ScoreBreakdown.java) |
| HTTP API          | `GET /api/properties/{id}/score`, `/score-explain`, `/api/search-profiles/{id}/scored-properties`     |
| Dart-модель       | `ScoredProperty` + `ScoreBreakdown` в [`search_profile.dart`](../frontend/lib/src/domain/search_profile.dart) |
| UI                | Маркеры `MapScreen`, breakdown в `PropertyDetailsScreen`                                            |

### Формула (v2.0)

```
totalScore = financial(0-20) + technical(0-20) + competitor(0-40) + synergy(0-15) + transport(0-5)
```

| Компонент          | Метод                              | Тип формулы                                |
|--------------------|------------------------------------|--------------------------------------------|
| Финансовый         | `calculateFinancial`               | Асимметричный exp decay (бюджет/площадь)   |
| Технический        | `calculateTechnical`               | Стартуем с max, вычитаем штрафы            |
| Конкуренты         | `analyzeNeighborhood`              | Distance-weighted Σ + exp decay            |
| Синергия           | `analyzeNeighborhood`              | Saturating Σ по категориям × норма         |
| Транспорт          | `calculateTransport`               | Лучший stop с distance-penalty per type    |

Полное описание формул и констант — в [04-services-business-logic.md §4.2](04-services-business-logic.md).

### Поток запроса

```
TENANT открыл MapScreen / PropertyDetailsScreen
   │
   ▼
GET /api/search-profiles/{id}/scored-properties
   │
   ▼ SearchProfileService.getScoredPropertiesForProfile
   ▼ PropertyScoreSnapshotService.scoreBatchWithSnapshot
   │
   ├─► L3 BATCH: findAllForBatch(profileId, version, [propertyIds])
   │    │  свежие → restoreFromSnapshot (БД payload_json + актуальный Property)
   │    └─ для не-свежих:
   │
   ▼ PropertyScoringService.scoreAndRankProperties (ForkJoinPool 8)
   ▼ для каждого помещения параллельно: scoreInternal
       │
       ▼ fetchAreaSnapshot — ОДИН Overpass-запрос на всё
       │   ▼ overpassPlacesService.searchAreaSnapshot(lat, lon, max(comp,syn,1500))
       │      │  L1 Caffeine HIT? → return
       │      │  L2 OverpassPersistentCache HIT? → return
       │      │  HTTP с multi-mirror + retry
       │      │  parseCombined → businesses + transportStops
       │      └─ persist в L2 (если не FAILED)
       │
       ├─► calculateFinancial (по profile.budget + property.price)
       ├─► calculateTechnical (по profile.requires* + property.has*)
       ├─► analyzeNeighborhood — конкуренты + синергия из снимка
       ├─► calculateTransport — лучший stop из снимка
       │
       └─► ScoredPropertyDto с breakdown + dataStatus
       
   ▼ saveSnapshot (если dataStatus != OVERPASS_UNAVAILABLE)
   ▼ возврат отсортированного списка
```

### Инвалидация

Snapshot'ы устаревают:
- **По TTL** (24ч).
- **По смене характеристик помещения** → `invalidateByProperty(propertyId)` в `PropertyService.updateProperty/deleteProperty`.
- **По смене критериев профиля** → `invalidateByProfile(profileId)` в `SearchProfileService.updateSearchProfile/deleteSearchProfile`.
- **По смене версии алгоритма** → `cleanupOnStartup()` при старте приложения удаляет `algorithm_version != current`.

### Уровни кэширования

| Уровень | Хранилище       | TTL    | Что хранит                                          |
|---------|------------------|--------|-----------------------------------------------------|
| L1      | Caffeine        | 60 мин | `OverpassAreaSnapshot` — снимок POI вокруг точки    |
| L2      | Postgres `overpass_cache` | 7 дней | Сериализованный snapshot                  |
| L3      | Postgres `property_score_snapshots` | 24 часа | Готовый `ScoredPropertyDto` (JSON payload) |

### Ключевое улучшение v2.0: честная обработка сбоев

Раньше при сбое Overpass начислялось 40 + 15 + 5 = 60 «бесплатных» баллов, и плохой адрес становился «🔥 Отличный мэтч!». Теперь:

```java
ScoredPropertyDto.DataStatus dataStatus = snapshot.isFailed()
        ? ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE
        : ScoredPropertyDto.DataStatus.COMPLETE;

if (dataStatus == OVERPASS_UNAVAILABLE) {
    total = financial.score() + technical.score();  // только то, что посчитано
    label = "⚠️ Частичная оценка — попробуйте позже";
    color = "gray";
}
```

UI показывает серый маркер `⚠️` и кнопку «Обновить оценку».

---

## 8.2. Геопоиск + двухслойный кэш Overpass

**Что делает:** для произвольной точки `(lat, lon, radius)` возвращает все POI (магазины, кафе, аптеки, ...) и транспортные узлы (метро, ж/д, трамвай, автобус) из OpenStreetMap.

### Где живёт

| Компонент                             | Файл                                                                                                 |
|---------------------------------------|------------------------------------------------------------------------------------------------------|
| Клиент API                            | [`OverpassPlacesService`](../backend/src/main/java/com/example/backend/service/OverpassPlacesService.java) |
| L2-кэш                                | [`OverpassPersistentCache`](../backend/src/main/java/com/example/backend/service/OverpassPersistentCache.java) |
| Сущность L2                           | [`OverpassCacheEntry`](../backend/src/main/java/com/example/backend/entity/OverpassCacheEntry.java)   |
| DTO снимка                            | [`OverpassAreaSnapshot`](../backend/src/main/java/com/example/backend/service/OverpassAreaSnapshot.java) |
| L1 (Caffeine config)                  | [`CacheConfig`](../backend/src/main/java/com/example/backend/config/CacheConfig.java)                |
| HTTP-клиент                           | [`RestClientConfig`](../backend/src/main/java/com/example/backend/config/RestClientConfig.java)      |
| Локальный Overpass-контейнер          | [`docker-compose.dev.yml`](../docker-compose.dev.yml)                                                |

### Архитектура снимка

```
                  POI (бизнесы)
                   │
   shop/amenity/  │  railway/highway/
   office/.../  ──┴── public_transport/...
   craft/
        │              │
        ▼              ▼
    NearbyBusiness   TransportStop
        │              │
        └──────┬───────┘
               │
       OverpassAreaSnapshot {
         businesses: List<NearbyBusiness>,
         transportStops: List<TransportStop>,
         status: OK | FAILED
       }
```

### Объединённый запрос

Один Overpass QL за всё:

```
[out:json][timeout:25];
(
  nwr[shop](around:R,LAT,LON);
  nwr[amenity~"^(pharmacy|cafe|restaurant|...)$"](around:R,LAT,LON);
  nwr[office~"^(...)$"](around:R,LAT,LON);
  nwr[healthcare~"^(...)$"](around:R,LAT,LON);
  nwr[leisure~"^(fitness_centre|sports_centre|...)$"](around:R,LAT,LON);
  nwr[craft](around:R,LAT,LON);
  nwr[tourism~"^(hotel|hostel|...)$"](around:R,LAT,LON);
  
  nwr[railway=station][name](around:R,LAT,LON);
  nwr[railway=subway_entrance][name](around:R,LAT,LON);
  nwr[railway=tram_stop](around:R,LAT,LON);
  nwr[highway=bus_stop](around:R,LAT,LON);
  nwr[public_transport=station][name](around:R,LAT,LON);
);
out tags center 3500;
```

Раньше делалось двумя независимыми HTTP-вызовами (отдельно бизнесы, отдельно транспорт). Сейчас — один round-trip, одна позиция в очереди Overpass.

### Multi-mirror + retry

```java
private String executeWithMirrorFallback(String query, ...) {
    for (int m = 0; m < mirrors.size(); m++) {
        String mirror = mirrors.get(m);
        for (int attempt = 1; attempt <= MAX_ATTEMPTS_PER_MIRROR; attempt++) {
            try {
                String body = overpassRestClient.post().uri(mirror)
                    .contentType(...).body(formBody).retrieve().body(String.class);
                if (body != null && !body.isBlank()) return body;
            } catch (Exception e) {
                log.warn("[OVERPASS] Сбой ...");
            }
            if (attempt < MAX_ATTEMPTS_PER_MIRROR) sleepBackoff(attempt);
        }
    }
    return null;  // все mirror'ы упали
}
```

В application.properties:

```properties
overpass.api.urls=${OVERPASS_API_URLS:http://localhost:12345/api/interpreter}
```

Сейчас зеркало одно — локальный Docker-контейнер `wiktorn/overpass-api` с PBF Центрального ФО (~40ГБ индекса на D:). Архитектура готова к подключению public mirror'ов (overpass-api.de, kumi.systems, private.coffee) через ENV без правки кода.

### Ключи кэша — бакетирование

```java
private String buildCacheKey(double lat, double lon, int radiusMeters) {
    long latKey = Math.round(lat * 1000);           // ~111м точности по широте
    long lonKey = Math.round(lon * 1000);           // ~67м по долготе в Москве
    int radiusBucket = Math.floorDiv(radiusMeters, 250);
    return latKey + "_" + lonKey + "_" + radiusBucket;
}
```

Адреса в одном квартале → одинаковый bucket → переиспользуют ответ Overpass. Это критично для плотных районов, где десятки помещений в одной точке.

### FAILED никогда не кэшируется

```java
@Cacheable(... unless = "#result == null || #result.isFailed()")
```

В Caffeine — `unless`. В Postgres — явная проверка в `put()`:

```java
public void put(String cacheKey, OverpassAreaSnapshot snapshot) {
    if (snapshot.isFailed()) return;
    // ...
}
```

Иначе временный сбой Overpass убил бы точку на 7 дней.

### Cleanup устаревших

```java
@Scheduled(cron = "0 0 3 * * *")
public void cleanupExpired() {
    LocalDateTime cutoff = LocalDateTime.now().minusHours(ttlHours);
    int removed = repository.deleteByCachedAtBefore(cutoff);
}
```

Каждый день в 03:00 удаляет L2-записи старше 7 дней. Без этого таблица растёт неограниченно.

---

## 8.3. Поисковые профили арендатора

**Что делает:** позволяет арендатору сохранить «проект поиска» (например, «Открыть кофейню на Арбате») с критериями (категория, бюджет, площадь, технические требования, радиус, желаемые соседи) и видеть скоринг помещений именно под этот профиль.

### Где живёт

| Слой        | Компонент                                                                                            |
|-------------|------------------------------------------------------------------------------------------------------|
| Сущность    | [`SearchProfile`](../backend/src/main/java/com/example/backend/entity/SearchProfile.java)            |
| Сервис      | [`SearchProfileService`](../backend/src/main/java/com/example/backend/service/SearchProfileService.java) |
| Контроллер  | [`SearchProfileController`](../backend/src/main/java/com/example/backend/controller/SearchProfileController.java) |
| DTO         | [`CreateSearchProfileRequest`](../backend/src/main/java/com/example/backend/dto/CreateSearchProfileRequest.java) |
| API         | `/api/search-profiles/**`                                                                            |
| Dart-модель | [`SearchProfile`](../frontend/lib/src/domain/search_profile.dart)                                    |
| Сервис      | [`SearchProfileService`](../frontend/lib/src/services/search_profile_service.dart) (frontend)        |
| UI          | [`SearchProfilesScreen`](../frontend/lib/src/presentation/screens/tenant/search_profiles_screen.dart) |

### Структура профиля

```
SearchProfile
├── name: "Открыть кофейню на Арбате"
├── businessCategory: Аптека (id=12)           // прямой конкурент
├── Финансы: minArea/maxArea, minBudget/maxBudget
├── Технические: requiresWater/Ventilation/Wc/Parking/LoadingZone/SeparateEntrance
│                minPowerKw, minCeilingHeight
├── Локация: centerLatitude, centerLongitude
│            searchRadiusMeters (для конкурентов)
│            synergyRadiusMeters (для синергии, опц.)
├── desiredNeighbors: {Университет, Бизнес-центр}  // синергия
└── isActive: true
```

### Что даёт активный профиль

При открытии **`/api/properties/recommended`**:

```java
public List<Property> getRecommendedPropertiesForTenant(Long tenantUserId) {
    List<Property> allPublished = propertyRepository.findByStatus(PropertyStatus.PUBLISHED);
    var activeProfiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantUserId);

    if (!activeProfiles.isEmpty()) {
        SearchProfile activeProfile = activeProfiles.get(0);
        return propertyScoreSnapshotService
                .scoreBatchWithSnapshot(activeProfile, allPublished, false)
                .stream()
                .map(ScoredPropertyDto::getProperty)
                .collect(Collectors.toList());
    }
    return allPublished;
}
```

Без активного профиля — просто все PUBLISHED без сортировки.

### Инвалидация snapshot'ов

`updateSearchProfile` и `deleteSearchProfile` вызывают `invalidateByProfile(profileId)`:

```java
@Transactional
public SearchProfile updateSearchProfile(Long tenantId, Long profileId, CreateSearchProfileRequest request) {
    SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);
    // ... обновляем все поля ...
    SearchProfile saved = searchProfileRepository.save(profile);
    propertyScoreSnapshotService.invalidateByProfile(profileId);   // 🔥
    return saved;
}
```

Это гарантирует, что при изменении критериев арендатор сразу видит оценки **под новые критерии**.

### UI-сценарий

```
SearchProfilesScreen (список)
  ↓ "+" FAB
Wizard создания
  ↓ 4 шага: основное / финансы / технические / локация+соседи
  ↓ submit
POST /api/search-profiles
  ↓ возврат на список
Выбор «активного» в MapScreen → Dropdown
  ↓ MapScreen.reloadProperties с profileId
GET /api/search-profiles/{id}/scored-properties (длинный, до 240с)
  ↓ маркеры на карте окрашиваются по баллам
```

---

## 8.4. Real-time чат + мультиканальная доставка

**Что делает:** арендатор и арендодатель общаются после подачи заявки. Каждая заявка → одна чат-комната. Сообщения доставляются мгновенно через WebSocket, плюс шлётся push (заглушка).

### Где живёт

| Слой        | Компонент                                                                                            |
|-------------|------------------------------------------------------------------------------------------------------|
| Сущности    | [`ChatRoom`](../backend/src/main/java/com/example/backend/entity/ChatRoom.java), [`ChatMessage`](../backend/src/main/java/com/example/backend/entity/ChatMessage.java) |
| Сервис      | [`ChatService`](../backend/src/main/java/com/example/backend/service/ChatService.java)               |
| Контроллер  | [`ChatController`](../backend/src/main/java/com/example/backend/controller/ChatController.java)      |
| WS-конфиг   | [`WebSocketConfig`](../backend/src/main/java/com/example/backend/config/WebSocketConfig.java)        |
| API         | `/api/chat/**` (REST) + `/ws` (STOMP)                                                                |
| Dart-сервис | [`ChatService`](../frontend/lib/src/services/chat_service.dart)                                      |
| UI          | [`ChatScreen`](../frontend/lib/src/presentation/screens/chat/chat_screen.dart)                       |

### Архитектура доставки

```
Tenant печатает + отправляет
   │
   ▼ ChatService.sendMessage (REST)
POST /api/chat/rooms/{roomId}/messages
   │
   ▼ ChatController.sendMessage
   ├─► chatService.saveMessage → INSERT chat_messages
   ├─► messagingTemplate.convertAndSend("/topic/chat/{roomId}", dto)
   │    ↓ broadcast
   │   все подписчики WS получают real-time
   │
   └─► notificationService.sendPushNotification(otherSideId, ...)
        (сейчас — лог-заглушка)

Landlord подключён к /topic/chat/{roomId} через STOMP
   ↓ ChatService.connectStomp в ChatScreen.initState
   ↓ stompClient.subscribe(callback)
   ↓ frame.body → ChatMessage.fromJson(json) → onMessage(msg)
   ↓ setState → UI обновляется
```

**Почему так:**
- REST POST одновременно **сохраняет** и **транслирует**. Один HTTP-запрос — два эффекта.
- WS только **получает**. Это упрощает auth (REST уже валидирует JWT).

### Дедупликация

```dart
_chatService.connectStomp(room.id, (message) {
  setState(() {
    if (!_messages.any((m) => m.id == message.id)) {
      _messages.add(message);
      _scrollToBottom();
    }
  });
});
```

Отправитель получает своё сообщение и через REST-response, и через WS-broadcast. Dedupe по `id` — простой и надёжный.

### Connection lifecycle

```dart
@override
void initState() {
  super.initState();
  _loadUserAndRoom();  // ← connect здесь
}

@override
void dispose() {
  _chatService.disconnectStomp();  // ← disconnect здесь
  super.dispose();
}
```

WS-подключение живёт ровно столько, сколько открыт `ChatScreen`. При уходе с экрана — `disconnect`. Это значит: сообщения, пришедшие, когда пользователь не в чате, **не доставляются в реал-тайме** — только при следующем открытии чата (через `getMessages`).

Для оффлайн-доставки нужен push (FCM), который сейчас заглушка.

---

## 8.5. Аналитика для арендодателя

**Что делает:** показывает арендодателю, как часто его помещения смотрят, добавляют в избранное, какие заявки приходят. С графиками за 30 дней.

### Где живёт

| Слой        | Компонент                                                                                            |
|-------------|------------------------------------------------------------------------------------------------------|
| Сущности    | [`PropertyViewEvent`](../backend/src/main/java/com/example/backend/entity/PropertyViewEvent.java), [`FavoriteEvent`](../backend/src/main/java/com/example/backend/entity/FavoriteEvent.java) |
| Сервис      | [`AnalyticsService`](../backend/src/main/java/com/example/backend/service/AnalyticsService.java)     |
| Контроллер  | [`AnalyticsController`](../backend/src/main/java/com/example/backend/controller/AnalyticsController.java) |
| DTO         | [`AnalyticsDto`](../backend/src/main/java/com/example/backend/dto/AnalyticsDto.java)                 |
| Dart-сервис | [`AnalyticsService`](../frontend/lib/src/services/analytics_service.dart)                            |
| UI          | [`AnalyticsScreen`](../frontend/lib/src/presentation/screens/landlord/analytics_screen.dart)         |

### Поток событий

```
TENANT открывает карточку
   │
   ▼ PropertyDetailsScreen.initState
   ▼ AnalyticsService.logPropertyView(propertyId)
POST /api/analytics/view/{propertyId}
   │
   ▼ analyticsService.logPropertyView
   ├─► найти Property
   ├─► найти Viewer (если есть Principal)
   └─► save PropertyViewEvent(property, viewer, NOW)

TENANT добавляет в избранное
   │
   ▼ PropertyService.addFavorite
   ▼ propertyService.addFavorite
   ├─► user.favoriteProperties.add(property)
   └─► if added: analyticsService.logFavoriteEvent(propertyId, tenantId)
        → save FavoriteEvent(property, tenant, NOW)
```

### Дедупликация просмотров

При выводе landlord-аналитики авторизованные просмотры **группируются по `(propertyId, viewerId)`** — повторное открытие одной карточки одним пользователем считается одним просмотром:

```java
private List<PropertyViewEvent> dedupeViewsByViewer(List<PropertyViewEvent> events) {
    // сортировка по timestamp ASC
    Set<String> seenPairs = new HashSet<>();
    List<PropertyViewEvent> result = new ArrayList<>();
    for (PropertyViewEvent e : sorted) {
        if (e.getViewer() == null) {
            result.add(e);  // анонимные считаются отдельно
            continue;
        }
        String key = e.getProperty().getId() + ":" + e.getViewer().getId();
        if (seenPairs.add(key)) result.add(e);
    }
    return result;
}
```

Анонимные события (без JWT при просмотре) **не дедуплицируются** — нечем сгруппировать.

### Сводка

```json
{
  "totalViewsLast30Days": 142,
  "totalFavoritesLast30Days": 18,
  "totalApplications": 25,
  "totalApplicationsLast30Days": 7,
  "totalUniqueMessengers": 5,
  "viewsByDate": {"2026-05-01": 5, "2026-05-02": 8, ...},
  "favoritesByDate": {...},
  "applicationsByDate": {...}
}
```

### UI

`AnalyticsScreen` с режимами:
- **Общая** (`propertyId == null`) — по всем неархивным помещениям.
- **Per-property** (`propertyId != null`) — по одному.

Графики через `fl_chart`:
- Bar chart — просмотры по датам.
- Line chart — избранное по датам.
- Bar chart — заявки по датам.

Pull-to-refresh — `RefreshIndicator` → `_load()` заново.

### Архивные исключены

```java
List<PropertyViewEvent> recentViews = dedupeViewsByViewer(propertyViewEventRepository
    .findByPropertyLandlordIdAndViewTimestampAfter(landlordId, thirtyDaysAgo)
    .stream()
    .filter(e -> isNotArchived(e.getProperty()))
    .collect(Collectors.toList()));
```

`ARCHIVED` помещения не влияют на статистику — это правильно: «архив» это soft-delete, и его не должно быть в активной аналитике.

---

## 8.6. AI-объяснение скоринга через OpenRouter

**Что делает:** арендатор видит в карточке кнопку «AI-объяснение». При тапе backend строит **structured factsheet** из breakdown'а скоринга, шлёт в LLM с жёстким промптом, получает **6 структурированных блоков** на русском.

### Где живёт

| Слой       | Компонент                                                                                            |
|------------|------------------------------------------------------------------------------------------------------|
| Сервис     | [`OpenRouterAiService`](../backend/src/main/java/com/example/backend/service/OpenRouterAiService.java) |
| HTTP       | [`RestClientConfig.openRouterRestClient`](../backend/src/main/java/com/example/backend/config/RestClientConfig.java) |
| DTO        | `ScoreExplainResponse { explanation }`                                                               |
| API        | `GET /api/properties/{id}/score-explain?profileId=...`                                               |
| Dart-метод | `PropertyService.explainScore` ([`property_service.dart`](../frontend/lib/src/services/property_service.dart)) |
| UI         | BottomSheet в `PropertyDetailsScreen`                                                                |

### Каскад моделей

```java
private static final List<String> MODEL_FALLBACK_CHAIN = List.of(
    "meta-llama/llama-3.3-70b-instruct:free",
    "qwen/qwen3-next-80b-a3b-instruct:free",
    "z-ai/glm-4.5-air:free"
);
```

OpenRouter принимает массив `models` (максимум 3 элемента) и **автоматически переключается** на следующую при 402/429/5xx. Llama 3.3 70B — приоритетная (лучшая связность на русском); Qwen3 и GLM-4.5 Air — fallback'и с реально работающим free-tier.

### Структура промпта

**6 жёстких блоков:**
- ФИНАНСЫ — 1–2 предложения, балл X/20.
- ТЕХНИКА — 1–2 предложения, балл X/20.
- КОНКУРЕНТЫ — 2–3 предложения, имена по правилу, балл X/40.
- СИНЕРГИЯ — 1–2 предложения, балл X/15.
- ТРАНСПОРТ — 1 предложение, балл X/5.
- ИТОГ — 1 предложение.

**Жёсткие правила** (в промпте):
- Заголовки точно как указано (ЗАГЛАВНЫМИ, без двоеточий и emoji в заголовках).
- Между блоками — одна пустая строка, внутри — сплошной текст.
- Конкурентов **поимённо**:
  - ≤ 5 — назвать каждого.
  - 6–15 — первые 5 и «и ещё N».
  - ≥ 16 — первые 3 и «и ещё N».
- **Только факты из секции FACTS**, ничего не выдумывать.
- Запрещены вводные слова и расплывчатости.

В промпте есть **полный пример** на других данных — few-shot learning повышает структурированность.

### Factsheet — структурированный input

```
Адрес: ул. Тверская 5
Параметры помещения: 80 м², 320000 ₽/мес, 15 кВт, потолки 3.2 м, ремонт — типовой.

ФИНАНСЫ 18/20:
- площадь 80 м² попадает в требуемый диапазон 50–80 м².
- цена 320000 ₽/мес укладывается в бюджет 250000–400000 ₽.

ТЕХНИКА 15/20:
- арендатор требовал парковка, в помещении не указано, −1.0 (половина).

КОНКУРЕНТЫ 28/40:
- прямые конкуренты (по близости) (22 всего, безымянных 4): «36,6», «Ригла», ...
- логика балла: distance-weighted exp-decay...

СИНЕРГИЯ 9/15:
- найдены желаемые соседи (3): «БЦ Москва», «МГУ», ...

ТРАНСПОРТ 5/5:
- метро «Тверская» в 220 м (бонус 5/5)...

ИТОГ: 75/100 (🔥 Отличный мэтч!).
```

LLM получает уже разложенные по блокам факты с баллами — её работа просто пересказать в человеческой форме.

### Обработка безымянных POI

```java
private boolean isUnnamedPlaceholder(String name) {
    return name.matches("^(shop|amenity|office|healthcare|leisure|craft|tourism)=.+");
}
```

Если в OSM нет тега `name`, мы кладём имя как `"amenity=pharmacy"`. Promtпт ловит такие плейсхолдеры и отдельно говорит LLM «и ещё N без названия» — чтобы не было нелепого «конкурент: amenity=pharmacy».

### Fallback

```java
private ScoreExplainResponse fallback() {
    return new ScoreExplainResponse("AI-анализ временно недоступен. Оценку можно интерпретировать по шкале баллов самостоятельно.");
}
```

Любая ошибка (нет ключа, 5xx, пустой ответ) → мягкая заглушка. Скоринг сам по себе не зависит от AI.

### Не кэшируется

Каждый запрос — новый вызов OpenRouter. Free-tier лимиты редко достигаются (один пользователь делает 1–2 запроса за сессию), но кэш на (propertyId, profileId, algorithmVersion) был бы разумной оптимизацией.

---

## 8.7. Мульти-аккаунт авторизация во Flutter

**Что делает:** пользователь может быть зарегистрирован под несколькими ролями (TENANT и LANDLORD одновременно с разными email'ами) и переключаться между ними без повторного логина, пока JWT каждого аккаунта жив.

### Где живёт

| Компонент                  | Файл                                                                                |
|----------------------------|-------------------------------------------------------------------------------------|
| Модель                     | [`SavedAccount`](../frontend/lib/src/domain/saved_account.dart)                     |
| Сервис                     | [`AuthService`](../frontend/lib/src/services/auth_service.dart) (методы мульти-аккаунта) |
| UI                         | [`LoginScreen`](../frontend/lib/src/presentation/screens/auth/login_screen.dart) — chip'ы аккаунтов |
| SplashScreen fallback      | [`main.dart`](../frontend/lib/main.dart) — `resumeSavedAccount` в цикле             |

### Структура

```dart
class SavedAccount {
  final String email;
  final String role;          // TENANT / LANDLORD
  final String token;         // JWT
  final String? displayName;  // имя/название компании
  final DateTime lastUsedAt;

  String get initials { /* первые буквы имени */ }
}
```

Хранится в `FlutterSecureStorage` под ключом `saved_accounts` как сериализованный JSON-массив.

### Жизненный цикл

```
1. Пользователь делает login(email, password, rememberMe=true)
   ↓
2. AuthService._activateSession(email, token, role)
   — write jwt_token, user_role, active_account_email
   ↓
3. AuthService._upsertSavedAccount(SavedAccount(...))
   — добавляет/обновляет в saved_accounts с lastUsedAt = NOW

4. Пользователь делает logout()
   — стирает jwt_token, user_role, active_account_email
   — saved_accounts ОСТАЁТСЯ
   
5. SplashScreen при следующем запуске:
   ↓ checkAutoLogin (remember_me=true + не истёк) → role
   ↓ или: for acc in savedAccounts: resumeSavedAccount(acc.email) → role
       — берёт JWT из SavedAccount, если не истёк, активирует сессию
   ↓ или: → LoginScreen с chip'ами savedAccounts

6. LoginScreen: тап на chip аккаунта
   ↓ resumeSavedAccount(email)
       — _activateSession + _upsertSavedAccount(copyWith(lastUsedAt: NOW))
   ↓ Navigator → TenantMainScreen / LandlordMainScreen
```

### Активный аккаунт vs сохранённый

- **Активный** — тот, чей JWT сейчас в `jwt_token`. Только один.
- **Сохранённые** — все, чьи JWT хранятся в `saved_accounts`. Могут быть любого срока, но при `resumeSavedAccount` проверяется `_isTokenExpired`.

### UX

В `LoginScreen` снизу — горизонтальная лента chip'ов с инициалами и displayName. Тап → переключение за ~100мс (нет network call, нужен только активный JWT). Долгое нажатие или меню → `removeSavedAccount` (стирает из списка).

При смене профиля (имя/название) — `_refreshActiveAccountName(name)` обновляет displayName активного аккаунта в `savedAccounts`:

```dart
Future<bool> updateProfile(String name, String phone, int? categoryId) async {
  // ... PUT /api/profiles/.../me ...
  if (response.statusCode == 200) {
    await _refreshActiveAccountName(name);   // 🔥
    return true;
  }
}
```

### Известное ограничение

JWT живёт 24 часа. После этого `resumeSavedAccount` вернёт null → пользователь увидит LoginScreen. **Нет refresh-token** — это надо вводить пароль заново. Партнёрская «мульти-аккаунт» работает только в течение сессии каждого JWT.

---

## 8.8. Деплой и эксплуатация

**Что делает:** backend разворачивается как Windows-сервис под NSSM, проксируется через Cloudflare Tunnel на публичный домен. Frontend собирается через Flutter и устанавливается на телефон APK'ом.

### Где живёт

| Компонент           | Файл / Ресурс                                                                          |
|---------------------|----------------------------------------------------------------------------------------|
| Скрипт установки    | `install-services.ps1` (NSSM install)                                                  |
| Backend JAR         | сборка `gradlew bootJar` (стандартный Spring Boot)                                     |
| Логи backend        | `backend/logs/stdout.log`, `backend/logs/stderr.log`                                   |
| Docker dev          | [`docker-compose.dev.yml`](../docker-compose.dev.yml)                                  |
| Frontend сборка     | `flutter build apk --release --dart-define=API_BASE_URL=https://api.magomedov.online`  |
| Конфиг туннеля      | `cloudflared/config.yml` (вне репозитория)                                             |

### Архитектура деплоя

```
┌─────────────────────────────────────────────────┐
│  Windows-машина пользователя (single host)     │
│                                                 │
│  ┌─────────────────────┐  ┌──────────────────┐ │
│  │ retail-backend       │  │ cloudflared      │ │
│  │  (NSSM, SYSTEM)      │  │  (NSSM, user)    │ │
│  │  Spring Boot         │  │  api.magomedov   │ │
│  │  localhost:8080      │◄─┤  .online         │ │
│  └─────────────────────┘  │  → :8080         │ │
│                            └──────────────────┘ │
│                                                 │
│  ┌─────────────────────┐  ┌──────────────────┐ │
│  │ PostgreSQL          │  │ overpass_local   │ │
│  │ Docker, :5434       │  │ Docker, :12345   │ │
│  │ retail_aggregator    │  │ PBF ЦФО (D:)     │ │
│  └─────────────────────┘  └──────────────────┘ │
└─────────────────────────────────────────────────┘
         ▲                          ▲
         │ HTTPS                    │ APK
         │                          │
    ┌────┴──────────────────────────┴────┐
    │  Android-телефоны пользователей    │
    │  https://api.magomedov.online      │
    └─────────────────────────────────────┘
```

### Стандартный цикл изменений

```
Изменение кода backend
   │
   ▼
.\gradlew.bat bootJar       (на user-аккаунте, без админа)
   │
   ▼
Пользователь в админ-PowerShell:
   Restart-Service retail-backend -Force
   │
   ▼
Проверка живости (без админа):
   Invoke-WebRequest https://api.magomedov.online/api/properties/2 -UseBasicParsing
   → ожидаем 200
   │
   ▼
Если нужно frontend:
   flutter build apk --release --dart-define=API_BASE_URL=https://api.magomedov.online
   → APK устанавливается на телефон
```

### Особенность: SYSTEM-сервис под NSSM

Backend работает от **SYSTEM** (NSSM так зарегистрирован). Обычный non-admin PowerShell получает **Access denied** на `Restart-Service`. UAC-elevation через `Start-Process -Verb RunAs` тоже не работает.

**Правило:** перезапуск делает **пользователь сам** в админ-PowerShell. AI-агент не пытается сам перезапустить, а просит сделать руками.

См. memory: [project-deploy-workflow](../../Users/User/.claude/projects/c--Games-street-retail-aggregator/memory/project_deploy_workflow.md), [feedback-no-service-restart](../../Users/User/.claude/projects/c--Games-street-retail-aggregator/memory/feedback_no_service_restart.md).

### Cloudflare Tunnel

`cloudflared` отдельный Windows-сервис, проксирует `https://api.magomedov.online` → `localhost:8080`. Бесплатный TLS-эндпоинт, доступный с любого устройства без локальной сети. Токен — в системном `cloudflared/config.yml`.

**Преимущества:**
- Не нужен публичный IP / открытые порты на роутере.
- Бесплатный TLS-сертификат.
- DDoS-защита от Cloudflare.

**Trade-off:** добавляет ~50–100мс latency на каждый запрос (туннельный hop).

### Логи

NSSM перенаправляет stdout/stderr backend'а в файлы:
- `backend/logs/stdout.log`
- `backend/logs/stderr.log`

Bizness-логи помечены префиксами для grep:
- `[OVERPASS]` — HTTP-запросы и mirror-фолбэки.
- `[OVERPASS-PCACHE]` — операции с L2-кэшем.
- `[SCORE-SNAP]` — операции с L3-кэшем.
- `[COMP-CTX]`, `[COMP-SCORE]`, `[COMP-EMPTY]`, `[COMP-NO-MATCH]` — детали скоринга конкурентов.
- `[SYNERGY]`, `[TRANSPORT]` — синергия и транспорт.
- `[AI]` — OpenRouter-вызовы.
- `[PUSH NOTIFICATION]` — заглушка push.

### Известные ограничения деплоя

1. **Single-host.** Нет горизонтального масштабирования. Caffeine-кэш не распределённый (что не критично, потому что L2 в Postgres покрывает рестарт).
2. **NSSM Windows-only.** Скрипты не переносимы на Linux.
3. **Cloudflare Tunnel — single point of failure.** При его сбое все мобильные клиенты теряют доступ.
4. **Сборка JAR требует JDK 21.** Системный путь жёстко прибит: `C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot`.
5. **Нет CI/CD.** Сборка и деплой делаются вручную.
6. **DB бэкапов нет.** PostgreSQL в Docker, потеря volume = потеря данных.

---

## 8.9. Сводная таблица всех фич

| Фича                                | Backend ключевой компонент               | Frontend ключевой компонент                |
|-------------------------------------|------------------------------------------|--------------------------------------------|
| Скоринг помещений                   | `PropertyScoringService`                 | `ScoredProperty` + `MapScreen` маркеры     |
| Геопоиск + Overpass-кэш             | `OverpassPlacesService` + `OverpassPersistentCache` | (опосредованно через скоринг)   |
| Поисковые профили                   | `SearchProfileService` + `SearchProfile` | `SearchProfilesScreen`                     |
| Real-time чат                       | `ChatService` + STOMP + WS-broadcast     | `ChatService` (Dart) + STOMP-клиент + `ChatScreen` |
| Аналитика landlord                  | `AnalyticsService` + dedupe              | `AnalyticsScreen` + fl_chart               |
| AI-объяснение                       | `OpenRouterAiService` + каскад моделей   | `PropertyService.explainScore` + bottomSheet |
| Мульти-аккаунт                      | (стандартный JWT auth)                   | `AuthService` + `SavedAccount` + chip'ы    |
| Деплой Windows-сервис                | NSSM + cloudflared                       | `flutter build apk --dart-define=`         |
| Регистрация с верификацией email    | `AuthService.register` + 6-цифр код + SMTP | `RegisterScreen` + `pinput`              |
| Заявки                              | `ApplicationService` + push (заглушка)   | `MyApplicationsScreen` / `IncomingApplicationsScreen` |
| Избранное + лог `FavoriteEvent`     | `PropertyService.addFavorite` + dedup    | `FavoritesScreen`                          |
| Фото помещений (лимит 10, главное)  | `PropertyImageService` + `FileStorageService` | `ImageHelper.pickImages` + multipart  |
| Аватары                             | `ProfileService.uploadAvatar`            | `ProfileScreen` + `AuthService.uploadAvatar` |

---

## 8.10. Точки роста (roadmap-кандидаты)

Список вещей, которые в коде сделаны как заглушка или заслуживают рефакторинга:

| Что                                              | Сейчас                                | Желаемое                                     |
|--------------------------------------------------|----------------------------------------|----------------------------------------------|
| **Push-уведомления**                             | `NotificationService` логирует         | Реальная FCM-интеграция                      |
| **`InfrastructureService`**                       | Legacy, идёт в public Overpass без кэша | Заменить на `OverpassPlacesService`         |
| **`FavoriteService` дубликат**                    | Дублирует часть `PropertyService`     | Удалить или консолидировать                  |
| **Refresh-token**                                | Нет — 24ч и логиниться заново         | Issued/refresh JWT pair                      |
| **DB migrations**                                | `ddl-auto=update`                     | Flyway/Liquibase                             |
| **`jwt.secret` default**                         | Жёсткий fallback в коде               | Только через ENV в production                |
| **Async email**                                  | Синхронный SMTP, падение SMTP роняет register | Очередь + retry                       |
| **State management в Flutter**                    | StatefulWidget + GlobalKey            | Riverpod/Provider/Bloc                       |
| **Dio Interceptor для авторизации**               | Ручной `headers: ...` в каждом методе | Один глобальный interceptor                  |
| **Кэш AI-объяснения**                            | Каждый запрос — новый вызов LLM        | Кэш на (propertyId, profileId, algorithmVersion) |
| **TTL-cleanup для `property_score_snapshots`**   | Только при смене algorithmVersion     | Дополнительно крон по TTL                    |
| **L4-кэш HTTP**                                  | Caffeine только overpass               | Кэш ответов `/api/properties/{id}` и `/api/categories` |
| **i18n**                                         | Хардкод русского                       | flutter_localizations + ARB                  |
| **CI/CD**                                        | Вручную                                | GitHub Actions: build + deploy               |
| **DB бэкапы**                                    | Нет                                    | `pg_dump` крон + S3                          |
| **`@ResponseStatus` exceptions**                  | RuntimeException → 500                 | Custom исключения с 403/404                  |
| **`@PreAuthorize` вместо ручных проверок**       | В сервисах `if (!ownerId.equals(...)) throw` | Декларативно через SpEL              |
| **Global STOMP в Flutter**                       | Один STOMP на ChatScreen               | Глобальный, чтобы сообщения приходили в офлайн UI |
| **OWASP / security audit**                       | CORS открыт `*`, нет rate-limit'а     | Сужение, rate-limit, security headers        |

---

## 8.11. Карта документов

| Раздел                                | Файл                                                       |
|---------------------------------------|------------------------------------------------------------|
| 1. Архитектура и инфраструктура       | [01-architecture-and-infrastructure.md](01-architecture-and-infrastructure.md) |
| 2. Безопасность и аутентификация      | [02-security-and-auth.md](02-security-and-auth.md)         |
| 3. Доменная модель                    | [03-domain-model.md](03-domain-model.md)                   |
| 4. Сервисы (бизнес-логика)            | [04-services-business-logic.md](04-services-business-logic.md) |
| 5. REST API                           | [05-rest-api.md](05-rest-api.md)                           |
| 6. Frontend — экраны                  | [06-frontend-screens.md](06-frontend-screens.md)           |
| 7. Frontend — сервисы и доменные модели | [07-frontend-services-and-domain.md](07-frontend-services-and-domain.md) |
| 8. Сквозные / «фичевые» темы          | [08-cross-cutting-features.md](08-cross-cutting-features.md) (этот файл) |
