# 04. Сервисы (бизнес-логика)

Документ описывает все `@Service`-классы и их роль в системе. Это сердце приложения: контроллеры — это тонкая HTTP-обёртка, а реальная бизнес-логика собрана здесь.

---

## 4.1. Карта сервисов

| Сервис                          | Главная ответственность                                                | Зависимости                                                    |
|---------------------------------|------------------------------------------------------------------------|----------------------------------------------------------------|
| `PropertyService`               | CRUD помещений, лендинг арендатора                                     | `PropertyScoringService`, `PropertyScoreSnapshotService`, `AnalyticsService` |
| `PropertyScoringService`        | Расчёт 5-компонентной оценки (0–100 баллов)                            | `OverpassPlacesService`, `BusinessCategoryRepository`          |
| `PropertyScoreSnapshotService`  | Кэш L3 готовых оценок в БД + батч-сценарии                            | `PropertyScoringService`, `PropertyScoreSnapshotRepository`    |
| `OverpassPlacesService`         | HTTP-клиент Overpass API с multi-mirror fallback, парсинг              | `OverpassPersistentCache`, `RestClient(overpass)`              |
| `OverpassPersistentCache`       | Кэш L2 OSM-ответов в Postgres (TTL 7 дней)                            | `OverpassCacheRepository`                                      |
| `SearchProfileService`          | CRUD проектов поиска арендатора + батч-скоринг                         | `PropertyScoreSnapshotService`                                 |
| `ApplicationService`            | Жизненный цикл заявок (PENDING → ACCEPTED/REJECTED)                    | `NotificationService`                                          |
| `ChatService`                   | Чат-комнаты и сообщения (REST + сохранение из WS)                      | `NotificationService`                                          |
| `NotificationService`           | Заглушка push-уведомлений (FCM не интегрирован)                        | —                                                              |
| `AnalyticsService`              | Лог просмотров/избранного, агрегация для landlord                     | event-репозитории                                              |
| `FavoriteService`               | Альтернативная точка управления избранным                              | `AnalyticsService`                                             |
| `ProfileService`                | CRUD профилей TenantProfile/LandlordProfile + аватары                  | `FileStorageService`                                           |
| `PropertyImageService`          | Загрузка/удаление фото помещений, главное фото                         | `FileStorageService`                                           |
| `FileStorageService`            | Сохранение/удаление файлов на ФС с валидацией                          | —                                                              |
| `CategoryService`               | Дерево и плоский список категорий бизнеса                              | `BusinessCategoryRepository`                                   |
| `OpenRouterAiService`           | AI-объяснение скоринга через OpenRouter (бесплатные LLM)               | `RestClient(openRouter)`                                       |
| `InfrastructureService`         | Legacy POI-поиск через публичный Overpass (заглушка)                   | `RestTemplate`                                                 |

---

## 4.2. `PropertyScoringService` — ядро бизнес-логики

[`PropertyScoringService.java`](../backend/src/main/java/com/example/backend/service/PropertyScoringService.java)

Главный сервис проекта. Считает оценку помещения под конкретный профиль поиска арендатора. **5 компонентов, итого 0–100 баллов:**

| Компонент          | Макс. балл | Что оценивает                                                          |
|--------------------|------------|------------------------------------------------------------------------|
| Финансовый         | 20         | Площадь и бюджет относительно диапазона арендатора                     |
| Технический        | 20         | Соответствие тех. требованиям (вода, мощность, потолки и т.д.)         |
| Конкуренты         | 40         | Прямые конкуренты вокруг точки (Overpass)                              |
| Синергия           | 15         | Близость желаемых соседей-категорий                                    |
| Транспорт          | 5          | Близость метро / ж/д / трамвая / автобуса                              |

**Версия алгоритма:**

```java
public static final String ALGORITHM_VERSION = "v2.0";
```

Меняется при изменении любой формулы. Все snapshot'ы старых версий автоматически инвалидируются при старте (см. §4.4).

### 4.2.1. Поток `scoreInternal`

```
                            scoreInternal(profile, property)
                                   │
        ┌─────────┬─────────┬──────┴──────┬─────────┬────────┐
        ▼         ▼         ▼             ▼         ▼        ▼
   Финансы   Техника   fetchAreaSnapshot  (один Overpass-запрос на всё)
                            │
                            ▼
                    OverpassAreaSnapshot {businesses, transportStops, status}
                            │
                ┌───────────┼───────────┐
                ▼           ▼           ▼
         Конкуренты    Синергия    Транспорт
                            │
                            ▼
                 ScoredPropertyDto {
                   totalScore, financial, technical,
                   competitor, synergy, transport,
                   directCompetitorNames, synergyNeighborNames,
                   matchLabel, matchColor, breakdown,
                   dataStatus, algorithmVersion
                 }
```

**Ключевая оптимизация:** один объединённый Overpass-запрос на помещение, объединяющий бизнесы и транспорт. Раньше было два независимых HTTP-запроса — два сетевых round-trip'a и две позиции в очереди Overpass.

```java
private OverpassAreaSnapshot fetchAreaSnapshot(SearchProfile profile, Property property) {
    if (property.getLatitude() == null || property.getLongitude() == null) {
        return new OverpassAreaSnapshot(List.of(), List.of(), OverpassAreaSnapshot.FetchStatus.OK);
    }
    int competitorRadius = profile.getSearchRadiusMeters() != null
            ? Math.min(profile.getSearchRadiusMeters(), 5000)
            : 1000;
    int synergyRadius = profile.getSynergyRadiusMeters() != null
            ? Math.min(profile.getSynergyRadiusMeters(), 5000)
            : competitorRadius;
    int radius = Math.max(Math.max(competitorRadius, synergyRadius), TRANSPORT_SEARCH_RADIUS_METERS);
    return overpassPlacesService.searchAreaSnapshot(
            property.getLatitude().doubleValue(),
            property.getLongitude().doubleValue(),
            radius);
}
```

### 4.2.2. Финансовый блок (0–20)

Половина баллов за бюджет, половина за площадь.

```java
private static final double BUDGET_AXIS_MAX = 10.0;
private static final double AREA_AXIS_MAX   = 10.0;
private static final double BUDGET_OVER_DECAY = 3.0;
private static final double AREA_UNDER_DECAY  = 4.0;
private static final double AREA_OVER_DECAY   = 1.5;
```

**Бюджет:**

```java
if (max == null || price.compareTo(max) <= 0) {
    if (min != null && price.compareTo(min) < 0) {
        return new BudgetEval(BUDGET_AXIS_MAX, "цена ниже минимума — это плюс");
    }
    return new BudgetEval(BUDGET_AXIS_MAX, "в бюджете");
}
double overRatio = price.subtract(max).doubleValue() / max.doubleValue();
double points = BUDGET_AXIS_MAX * Math.exp(-BUDGET_OVER_DECAY * overRatio);
```

- Цена в бюджете или ниже → полные 10/10.
- Цена выше max → плавный exp-decay: при overRatio=0.33 (цена на 33% выше) остаётся ~3.7 балла, при overRatio=1 (вдвое больше) — ~0.5.

**Площадь — асимметрия:**

```java
// если ниже min — decay=4 (мелкое помещение сильно штрафуется)
double points = AREA_AXIS_MAX * Math.exp(-AREA_UNDER_DECAY * deficit);

// если выше max — decay=1.5 (большое помещение терпимее: можно использовать частично)
double points = AREA_AXIS_MAX * Math.exp(-AREA_OVER_DECAY * overRatio);
```

Превышение площади мягче, чем недостаток. Это согласуется с практикой: 60м² когда хотел 80 — ок (часть можно не использовать); 30 когда хотел 80 — реальная проблема.

### 4.2.3. Технический блок (0–20)

Стартуем с 20 баллов, вычитаем штрафы.

```java
private static final double UNKNOWN_FIELD_PENALTY_FACTOR = 0.5;
private static final double CEILING_FULL_PENALTY_DEFICIT_M = 0.3;

private TechnicalResult calculateTechnical(SearchProfile profile, Property property) {
    List<ScoreBreakdown.TechnicalItem> items = new ArrayList<>();
    double score = MAX_TECHNICAL_SCORE;

    score -= addBoolItem(items, "вода",            profile.getRequiresWater(),            property.getHasWater(),            4);
    score -= addBoolItem(items, "вытяжка",         profile.getRequiresVentilation(),      property.getHasVentilation(),      4);
    score -= addBoolItem(items, "отдельный вход",  profile.getRequiresSeparateEntrance(), property.getHasSeparateEntrance(), 3);
    score -= addBoolItem(items, "санузел",         profile.getRequiresWc(),               property.getHasWc(),               3);
    score -= addBoolItem(items, "парковка",        profile.getRequiresParking(),          property.getHasParking(),          2);
    score -= addBoolItem(items, "зона разгрузки",  profile.getRequiresLoadingZone(),      property.getHasLoadingZone(),      2);
    score -= addPowerItem(items, profile.getMinPowerKw(), property.getPowerKw());
    score -= addCeilingItem(items, profile.getMinCeilingHeight(), property.getCeilingHeight());
    // ...
}
```

**Веса штрафов:**

| Требование          | Полный штраф |
|---------------------|--------------|
| Вода                | 4            |
| Вытяжка             | 4            |
| Отдельный вход      | 3            |
| Санузел             | 3            |
| Парковка            | 2            |
| Зона разгрузки      | 2            |
| Мощность            | 3 (градиент) |
| Потолки             | 2 (градиент) |

**Half-penalty для null:**

```java
private double addBoolItem(...) {
    if (!Boolean.TRUE.equals(required)) return 0;
    if (Boolean.TRUE.equals(actual)) return 0;
    else if (actual == null) {
        penalty = full * UNKNOWN_FIELD_PENALTY_FACTOR;
        reason  = "не указано (половина штрафа)";
    } else {
        penalty = full;
        reason  = "отсутствует";
    }
    // ...
}
```

Когда landlord не заполнил поле — берётся половина полного штрафа. Это «uncertainty discount»: справедливо, потому что отсутствие может означать и «у нас нет», и «забыли заполнить».

**Градиентные штрафы (мощность, потолки):**

```java
private double addPowerItem(...) {
    if (act >= req) return 0;
    double deficit = 1.0 - ((double) act / req);
    penalty = 3.0 * Math.min(1.0, Math.max(0.0, deficit));
}

private double addCeilingItem(...) {
    double deficitMeters = required.subtract(actual).doubleValue();
    double factor = Math.min(1.0, deficitMeters / CEILING_FULL_PENALTY_DEFICIT_M);
    penalty = 2.0 * factor;
}
```

Дефицит 50% мощности → 1.5 штрафа (не 3). Потолки ниже на 30 см → полный штраф 2.0, на 15 см → 1.0.

### 4.2.4. Компонент «Конкуренты» (0–40)

Самый сложный блок: distance-weighted exponential decay.

```java
private static final double DISTANCE_SIGMA_DIVISOR = 3.0;
private static final double COMPETITOR_DECAY_K_DIRECT = 1.0;
private static final double FALLBACK_WEIGHT_MISSING_COORDS = 0.2;
```

**Алгоритм:**

1. Из Overpass-снимка взять все POI вокруг точки.
2. По OSM-тегам каждого POI определить, является ли он **прямым конкурентом** (т.е. совпадает с `target.businessCategory` или принадлежит ей как дочерней).
3. Для каждого конкурента вычислить distance-weight:

```java
private double distanceWeight(double propertyLat, double propertyLon, NearbyBusiness business, double sigma) {
    if (bLat == 0.0 && bLon == 0.0) return FALLBACK_WEIGHT_MISSING_COORDS;
    double dist = haversineMeters(propertyLat, propertyLon, bLat, bLon);
    return Math.exp(-dist / sigma);
}
```

`sigma = max(radius/3, 50)`. В радиусе 1000м: σ=333м.
- Конкурент в 100м → weight ≈ 0.74
- Конкурент в 333м → weight ≈ 0.37 (1/e)
- Конкурент в 1000м → weight ≈ 0.05

4. Суммарный взвешенный вклад: `weightedDirect = Σ weight_i`.
5. Итоговый балл:

```java
double competitorScoreD = MAX_COMPETITOR_SCORE * Math.exp(-COMPETITOR_DECAY_K_DIRECT * weightedDirect);
```

- 0 конкурентов → 40/40.
- weightedDirect=1 (один близкий) → 14.7/40.
- weightedDirect=3 → 2/40.

**Логика «прямого конкурента» — учёт иерархии:**

```java
if (targetIsRoot) {
    // Если арендатор задал корневую категорию (например, «Еда и напитки»),
    // любая подкатегория из этого корня — прямой конкурент.
    if (targetId.equals(matchedParentId) || targetId.equals(catId)) {
        isDirect = true;
    }
} else {
    // Если задана листовая категория (например, «Аптека»), только точное совпадение.
    if (catId.equals(targetId)) {
        isDirect = true;
    }
}
```

**Score impact на каждого конкурента:**

```java
double totalLost = MAX_COMPETITOR_SCORE - competitorScoreD;
if (weightedDirect > 0.0) {
    for (int i = 0; i < directRanked.size(); i++) {
        double wRaw = directRawWeights.get(i);
        double impact = -totalLost * (wRaw / weightedDirect);
        directRanked.get(i).setScoreImpact(round2(impact));
    }
}
```

Каждому конкуренту в `breakdown.competitor.directRefs` присваивается его «вклад в потерю баллов». UI может показать «этот конкурент стоил вам -3.2 балла» в tooltip'е.

### 4.2.5. Компонент «Синергия» (0–15)

Насыщающаяся сумма весов на категорию.

```java
private static final double SYNERGY_SATURATION_K = 0.7;

if (desiredNeighborIds.isEmpty()) {
    synergyScore = MAX_SYNERGY_SCORE;  // не задано → max по умолчанию
} else {
    double sumPerCategory = 0.0;
    for (Long catId : desiredNeighborIds) {
        Double totalW = synergyTotalPerCategory.get(catId);
        double pc = totalW == null ? 0.0 : 1.0 - Math.exp(-totalW / SYNERGY_SATURATION_K);
        sumPerCategory += pc;
    }
    double normalized = sumPerCategory / desiredNeighborIds.size();
    double synergyScoreD = MAX_SYNERGY_SCORE * normalized;
}
```

**Идея:** для каждой желаемой категории берётся `1 - exp(-totalW/0.7)`, что **насыщается на 1** при большом числе соседей этой категории. То есть третий и четвёртый университет рядом дают меньше, чем первый — это правильно: с точки зрения «синергии» хватает одного-двух хороших соседей.

Итог нормализуется на число желаемых категорий — это позволяет арендатору задавать произвольное число `desiredNeighbors` без перекоса баллов.

### 4.2.6. Компонент «Транспорт» (0–5)

```java
private static final double TRANSPORT_SIGMA_METERS = 500.0;
private static final int TRANSPORT_SEARCH_RADIUS_METERS = 1500;
```

Фиксированный радиус 1500м (не из профиля). UX-обоснование: даже если бизнес-радиус арендатора 300м, важно знать «есть ли метро в 800м» — это всё ещё хорошо.

**Тип транспорта влияет на «эффективную дистанцию»** через `distancePenalty`:

```java
enum TransportType {
    METRO(1.0),  // метро самое ценное
    RAIL(1.1),
    TRAM(1.4),
    BUS(2.0);    // автобус в 200м ≈ метро в 400м
}
```

**Поиск лучшей остановки:**

```java
for (TransportStop stop : stops) {
    double d = haversineMeters(lat, lon, stop.lat(), stop.lon());
    if (d > TRANSPORT_SEARCH_RADIUS_METERS) continue;
    double eff = d * stop.type().getDistancePenalty();
    if (eff < bestEffective) {
        bestEffective = eff;
        bestRealDistance = d;
        best = stop;
    }
}

double pointsD = MAX_TRANSPORT_SCORE * Math.exp(-bestEffective / TRANSPORT_SIGMA_METERS);
```

- Метро в 100м → eff=100 → ~4.1/5.
- Метро в 500м → eff=500 → ~1.8/5.
- Автобус в 100м → eff=200 → ~3.4/5.

### 4.2.7. Обработка FAILED-статуса Overpass

Ключевое изменение в v2.0: при сбое Overpass **НЕ выставляется** max-балл «нет конкурентов = 40/40».

```java
ScoredPropertyDto.DataStatus dataStatus = snapshot.isFailed()
        ? ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE
        : ScoredPropertyDto.DataStatus.COMPLETE;

if (dataStatus == ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE) {
    total = financial.score() + technical.score();  // только то, что реально посчитано
    label = "⚠️ Частичная оценка — попробуйте позже";
    color = "gray";
}
```

Раньше при сбое начислялось 40+15+5=60 «бесплатных» баллов, и плохой адрес выглядел отличным мэтчем. Теперь честная неполная оценка с предупреждением.

### 4.2.8. Параллелизм

```java
public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
    // Принудительно инициализируем lazy-ассоциации профиля до выхода
    // в параллельный пул — параллельные треды могут не иметь Hibernate
    // session-а от OSIV, что выльется в LazyInitializationException.
    if (profile.getBusinessCategory() != null) profile.getBusinessCategory().getName();
    if (profile.getDesiredNeighbors() != null) profile.getDesiredNeighbors().size();
    properties.forEach(p -> { if (p.getImages() != null) p.getImages().size(); });

    ForkJoinPool pool = new ForkJoinPool(8);
    try {
        return pool.submit(() -> properties.parallelStream()
                .map(p -> scoreInternal(profile, p, tagIndex))
                .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
                .collect(Collectors.toList())
        ).join();
    } finally {
        pool.shutdown();
    }
}
```

- Кастомный `ForkJoinPool(8)` — чтобы не нагружать common-pool (он может быть занят другими параллельными стримами).
- 8 потоков — компромисс между wall-clock временем (для батча 50 помещений падает с 50×30с до ~8×30с) и нагрузкой на Overpass.
- HTTP-клиент Overpass работает на отдельном пуле `Executors.newFixedThreadPool(16)` (см. [01-architecture-and-infrastructure.md §1.7.2](01-architecture-and-infrastructure.md)).

### 4.2.9. Лейблы и цвета

```java
private String resolveMatchLabel(int score) {
    if (score >= 75) return "🔥 Отличный мэтч!";
    if (score >= 50) return "👍 Хороший вариант";
    if (score >= 25) return "⚠️ Частичное совпадение";
    return "❌ Не подходит";
}

private String resolveMatchColor(int score) {
    if (score >= 75) return "green";
    if (score >= 50) return "yellow";
    return "red";
}
```

Используются на фронте для бейджа в карточке. `breakdown` несёт детали для tooltip'а.

---

## 4.3. `OverpassPlacesService` — клиент OSM API

[`OverpassPlacesService.java`](../backend/src/main/java/com/example/backend/service/OverpassPlacesService.java)

### Основные возможности

- **Multi-mirror fallback.** CSV `overpass.api.urls` пробует список зеркал по порядку.
- **Retry с exp-backoff.** Внутри каждого mirror'а — до 2 попыток с backoff'ом 500мс → 1000мс.
- **Caffeine L1 + Postgres L2 кэширование.**
- **FAILED-статус.** Корректно отличает «вокруг ничего нет» от «API не отвечает».

### Главный метод

```java
@Cacheable(
        value = "overpassArea",
        key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + " +
              "T(Math).floorDiv(#radiusMeters, 250)",
        unless = "#result == null || #result.isFailed()"
)
public OverpassAreaSnapshot searchAreaSnapshot(double lat, double lon, int radiusMeters) {
    String cacheKey = buildCacheKey(lat, lon, radiusMeters);

    // L2 — постоянный кэш в PostgreSQL
    var fromDb = persistentCache.get(cacheKey);
    if (fromDb.isPresent()) {
        log.debug("[OVERPASS] DB-cache hit (key={})", cacheKey);
        return fromDb.get();
    }

    String query = buildCombinedQuery(lat, lon, radiusMeters);
    String body = executeWithMirrorFallback(query, lat, lon, radiusMeters);
    if (body == null) {
        log.warn("[OVERPASS] Все mirror'ы недоступны (lat={}, lon={}, r={}м)", lat, lon, radiusMeters);
        return OverpassAreaSnapshot.failed();
    }
    OverpassAreaSnapshot parsed = parseCombined(body);
    persistentCache.put(cacheKey, parsed);
    return parsed;
}
```

**Особенности `@Cacheable`:**

- `key` — SpEL-выражение с бакетированием по 0.001° по lat/lon и 250м по радиусу. Соседние точки в одном квартале → один ключ → переиспользуют кэш.
- `unless = "#result.isFailed()"` — FAILED-снимки **не кэшируются** в Caffeine. Иначе один сбой Overpass «прибил» бы точку на час.

**Порядок чтения:**

```
L1 (Caffeine)  ──HIT──► return  (микросекунды)
     │ MISS
     ▼
L2 (Postgres)  ──HIT──► return + L1 cached (3–10 мс)
     │ MISS
     ▼
HTTP к Overpass с multi-mirror + retry  (300мс — 30с)
     │ SUCCESS → parse → L2.put + L1 cached
     │ FAILURE
     ▼
OverpassAreaSnapshot.failed() (НЕ кэшируется)
```

### Multi-mirror fallback

```java
private String executeWithMirrorFallback(String query, ...) {
    for (int m = 0; m < mirrors.size(); m++) {
        String mirror = mirrors.get(m);
        for (int attempt = 1; attempt <= MAX_ATTEMPTS_PER_MIRROR; attempt++) {
            try {
                String body = overpassRestClient.post()
                        .uri(mirror)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("User-Agent", "street-retail-aggregator/1.0 (scoring)")
                        .header("Accept", "application/json")
                        .body(formBody)
                        .retrieve()
                        .body(String.class);

                if (body != null && !body.isBlank()) return body;
            } catch (Exception e) {
                log.warn("[OVERPASS] Сбой {} (попытка {}/{}): {}", mirror, attempt, MAX_ATTEMPTS_PER_MIRROR, e.getMessage());
            }
            if (attempt < MAX_ATTEMPTS_PER_MIRROR) sleepBackoff(attempt);
        }
    }
    return null;
}
```

В текущем application.properties mirror только один (`localhost:12345`), но архитектура готова к падению на public-mirror'ы.

### Объединённый Overpass QL

```java
private String buildCombinedQuery(double lat, double lon, int radiusMeters) {
    String around = "around:" + radiusMeters + "," + lat + "," + lon;
    StringBuilder q = new StringBuilder("[out:json][timeout:25];(");

    // Бизнесы
    q.append("nwr[shop](").append(around).append(");");
    q.append("nwr[amenity~\"^(").append(joinAlt(AMENITY_VALUES)).append(")$\"](").append(around).append(");");
    q.append("nwr[office~\"^(").append(joinAlt(OFFICE_VALUES)).append(")$\"](").append(around).append(");");
    q.append("nwr[healthcare~\"^(").append(joinAlt(HEALTHCARE_VALUES)).append(")$\"](").append(around).append(");");
    q.append("nwr[leisure~\"^(").append(joinAlt(LEISURE_VALUES)).append(")$\"](").append(around).append(");");
    q.append("nwr[craft](").append(around).append(");");
    q.append("nwr[tourism~\"^(").append(joinAlt(TOURISM_VALUES)).append(")$\"](").append(around).append(");");

    // Транспорт
    q.append("nwr[railway=station][name](").append(around).append(");");
    q.append("nwr[railway=subway_entrance][name](").append(around).append(");");
    q.append("nwr[railway=tram_stop](").append(around).append(");");
    q.append("nwr[highway=bus_stop](").append(around).append(");");
    q.append("nwr[public_transport=station][name](").append(around).append(");");

    q.append(");out tags center 3500;");
    return q.toString();
}
```

- `nwr` — Nodes + Ways + Relations.
- `[name]` для метро/жд/PT — иначе ловятся технические узлы без имени.
- `tram_stop`/`bus_stop` — без `[name]`, т.к. часто остановки не имеют тега name в OSM-Москвы.
- `out tags center 3500` — отдать только теги (без геометрии) и центр для way/relation, лимит 3500 элементов.

### Парсинг

```java
private OverpassAreaSnapshot parseCombined(String body) {
    // dedup: один OSM-объект может быть и amenity, и building.
    Map<String, NearbyBusiness> businessById = new LinkedHashMap<>();
    Map<String, TransportStop> transportById = new LinkedHashMap<>();

    for (JsonNode el : elements) {
        String key = type + ":" + id;
        // 1) Сначала пробуем как транспортный узел
        TransportStop.TransportType stopType = classifyTransport(tags);
        if (stopType != null) {
            transportById.putIfAbsent(key, new TransportStop(name, stopType, coords[0], coords[1]));
            continue;
        }
        // 2) Иначе классифицируем как бизнес
        List<String> rubrics = extractRubrics(tags);
        if (rubrics.isEmpty()) continue;
        businessById.putIfAbsent(key, new NearbyBusiness(name, rubrics, coords[0], coords[1]));
    }
    // ...
}
```

**Тонкости:**

- **Дедупликация** по `(type, id)` — один OSM-объект может иметь несколько тегов, попадающих под разные фильтры.
- **Транспорт имеет приоритет** перед бизнесами (хотя пересечений в фильтре нет).
- **Best-name** — приоритет `name:ru` > `name` > `brand` > `operator` > `official_name` > `short_name`.
- **Для транспорта** не используется `operator`/`brand` — иначе получим «ГУП Московский метрополитен» вместо названия станции.

### `OverpassAreaSnapshot`

[`OverpassAreaSnapshot.java`](../backend/src/main/java/com/example/backend/service/OverpassAreaSnapshot.java):

```java
public record OverpassAreaSnapshot(
        List<NearbyBusiness> businesses,
        List<TransportStop> transportStops,
        FetchStatus status
) {
    public enum FetchStatus { OK, FAILED }

    public static OverpassAreaSnapshot failed() {
        return new OverpassAreaSnapshot(List.of(), List.of(), FetchStatus.FAILED);
    }

    public boolean isFailed() { return status == FetchStatus.FAILED; }
}
```

Java record с явным `FetchStatus`. Скорер не должен путать «вокруг пусто» и «API лежит».

---

## 4.4. `OverpassPersistentCache` — L2-кэш

[`OverpassPersistentCache.java`](../backend/src/main/java/com/example/backend/service/OverpassPersistentCache.java)

### Цель

После рестарта backend Caffeine пуст. Без этого слоя весь скоринг бил бы по публичным mirror'ам Overpass с холодным стартом. PostgreSQL-кэш на 7 дней решает эту проблему.

### `get(cacheKey)` — чтение с TTL-фильтром

```java
@Transactional(readOnly = true)
public Optional<OverpassAreaSnapshot> get(String cacheKey) {
    Optional<OverpassCacheEntry> entry = repository.findByCacheKey(cacheKey);
    if (entry.isEmpty()) return Optional.empty();

    OverpassCacheEntry e = entry.get();
    LocalDateTime cutoff = LocalDateTime.now().minusHours(ttlHours);
    if (e.getCachedAt().isBefore(cutoff)) {
        // Устаревшая запись — игнорируем
        return Optional.empty();
    }
    try {
        OverpassAreaSnapshot snapshot = objectMapper.readValue(e.getResponseJson(), OverpassAreaSnapshot.class);
        return Optional.of(snapshot);
    } catch (Exception ex) {
        // Битая запись — не эвиктим здесь (readOnly + self-invocation = не сработает),
        // следующий put() перепишет.
        log.warn("[OVERPASS-PCACHE] Ошибка десериализации key={}: {}", cacheKey, ex.getMessage());
        return Optional.empty();
    }
}
```

### `put(cacheKey, snapshot)` — upsert

```java
@Transactional
public void put(String cacheKey, OverpassAreaSnapshot snapshot) {
    if (snapshot.isFailed()) return;  // FAILED не кэшируем
    try {
        String json = objectMapper.writeValueAsString(snapshot);
        Optional<OverpassCacheEntry> existing = repository.findByCacheKey(cacheKey);
        OverpassCacheEntry entry = existing.orElseGet(() -> OverpassCacheEntry.builder()
                .cacheKey(cacheKey).build());
        entry.setResponseJson(json);
        entry.setCachedAt(LocalDateTime.now());
        repository.save(entry);
    } catch (Exception ex) {
        log.warn("[OVERPASS-PCACHE] Ошибка сохранения key={}: {}", cacheKey, ex.getMessage());
    }
}
```

- **FAILED не сохраняется.** Симметрично Caffeine'у — иначе сбой Overpass «прибьёт» точку на 7 дней.
- **Upsert через find+save** вместо native ON CONFLICT — портабельно, не зависит от диалекта.

### Фоновая очистка

```java
@Scheduled(cron = "0 0 3 * * *")
@Transactional
public void cleanupExpired() {
    LocalDateTime cutoff = LocalDateTime.now().minusHours(ttlHours);
    int removed = repository.deleteByCachedAtBefore(cutoff);
    if (removed > 0) {
        log.info("[OVERPASS-PCACHE] Удалено {} устаревших записей (старше {} ч)", removed, ttlHours);
    }
}
```

Ежедневно в 03:00. Без cleanup'а таблица растёт неограниченно: каждая новая точка/радиус — новый `cache_key`.

---

## 4.5. `PropertyScoreSnapshotService` — L3-кэш

[`PropertyScoreSnapshotService.java`](../backend/src/main/java/com/example/backend/service/PropertyScoreSnapshotService.java)

Кэширующая обёртка вокруг `PropertyScoringService`. Сохраняет посчитанные оценки в БД и переиспользует их, пока:
1. Свежие по TTL (24ч).
2. Совпадает версия алгоритма.
3. Не было явной инвалидации.

### Зачем нужен

| Сценарий                                                                          | Без snapshot          | Со snapshot         |
|-----------------------------------------------------------------------------------|-----------------------|---------------------|
| Арендатор открыл список и отскроллил его 5 раз                                    | 5 × Overpass-вызовы   | 1 × Overpass + 4 × DB lookup |
| Открыть карточку → закрыть → открыть снова                                        | 2 × ~30c              | 30с + ~10мс         |
| Холодный список 50 помещений после рестарта (Caffeine пуст, но L2/L3 живы)        | 50 × HTTP             | 50 × DB lookup      |

### `scoreWithSnapshot(profile, property, force)` — единичный путь

```java
@Transactional
public ScoredPropertyDto scoreWithSnapshot(SearchProfile profile, Property property, boolean force) {
    Long propertyId = property.getId();
    Long profileId = profile.getId();
    String version = PropertyScoringService.ALGORITHM_VERSION;

    if (!force) {
        Optional<PropertyScoreSnapshot> existing =
                repository.findByPropertyIdAndProfileIdAndAlgorithmVersion(propertyId, profileId, version);
        if (existing.isPresent() && isFresh(existing.get())) {
            ScoredPropertyDto restored = restoreFromSnapshot(existing.get(), property);
            if (restored != null) return restored;
        }
    }

    ScoredPropertyDto fresh = scoringService.scorePropertyWithGis(profile, property);
    saveSnapshot(propertyId, profileId, fresh);
    return fresh;
}
```

Параметр `force=true` форсирует пересчёт (для кнопки «обновить оценку» на фронте).

### `scoreBatchWithSnapshot(profile, properties, force)` — батч

Критическая оптимизация: один IN-запрос для N помещений вместо N отдельных.

```java
@Transactional
public List<ScoredPropertyDto> scoreBatchWithSnapshot(SearchProfile profile, List<Property> properties, boolean force) {
    if (properties.isEmpty()) return List.of();

    Long profileId = profile.getId();
    String version = PropertyScoringService.ALGORITHM_VERSION;

    Map<Long, Property> byId = properties.stream()
            .collect(Collectors.toMap(Property::getId, p -> p, (a, b) -> a, LinkedHashMap::new));

    Map<Long, ScoredPropertyDto> resolved = new HashMap<>();
    List<Property> toCompute = new ArrayList<>();

    if (force) {
        toCompute.addAll(properties);
    } else {
        List<PropertyScoreSnapshot> existing = repository.findAllForBatch(
                profileId, version, new ArrayList<>(byId.keySet()));
        Set<Long> resolvedIds = new HashSet<>();
        for (PropertyScoreSnapshot snap : existing) {
            if (!isFresh(snap)) continue;
            Property prop = byId.get(snap.getPropertyId());
            if (prop == null) continue;
            ScoredPropertyDto restored = restoreFromSnapshot(snap, prop);
            if (restored != null) {
                resolved.put(snap.getPropertyId(), restored);
                resolvedIds.add(snap.getPropertyId());
            }
        }
        for (Property p : properties) {
            if (!resolvedIds.contains(p.getId())) toCompute.add(p);
        }
    }

    if (!toCompute.isEmpty()) {
        List<ScoredPropertyDto> fresh = scoringService.scoreAndRankProperties(profile, toCompute);
        for (ScoredPropertyDto dto : fresh) {
            resolved.put(dto.getProperty().getId(), dto);
            saveSnapshot(dto.getProperty().getId(), profileId, dto);
        }
    }

    return resolved.values().stream()
            .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
            .collect(Collectors.toList());
}
```

### Сохранение `saveSnapshot`

```java
private void saveSnapshot(Long propertyId, Long profileId, ScoredPropertyDto dto) {
    // OVERPASS_UNAVAILABLE НЕ сохраняем — следующий запрос должен попробовать снова.
    if (dto.getDataStatus() == ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE) return;
    try {
        // Сериализуем без property — оно тяжёлое.
        ScoredPropertyDto copy = cloneWithoutProperty(dto);
        String json = objectMapper.writeValueAsString(copy);
        // ... upsert через find+save ...
    } catch (Exception e) {
        log.warn("[SCORE-SNAP] Ошибка сохранения snapshot ...");
    }
}
```

- **OVERPASS_UNAVAILABLE не сохраняется.** Следующий запрос должен ретраить, а не показывать «частичную оценку» из БД.
- **`property` исключается из payload** — при чтении мы подтягиваем актуальный объект через `PropertyRepository`, чтобы получить свежую цену/картинки.

### Инвалидация

```java
@Transactional
public void invalidateByProperty(Long propertyId) {
    int removed = repository.deleteByPropertyId(propertyId);
}

@Transactional
public void invalidateByProfile(Long profileId) {
    int removed = repository.deleteByProfileId(profileId);
}
```

Вызывается:
- `PropertyService.updateProperty` / `deleteProperty` → `invalidateByProperty`.
- `SearchProfileService.updateSearchProfile` / `deleteSearchProfile` → `invalidateByProfile`.

### Очистка на старте

```java
@EventListener(ApplicationReadyEvent.class)
@Transactional
public void cleanupOnStartup() {
    int removed = repository.deleteByOldAlgorithmVersion(PropertyScoringService.ALGORITHM_VERSION);
    if (removed > 0) {
        log.info("[SCORE-SNAP] Очищено {} snapshot'ов от устаревших версий алгоритма (текущая: {})",
                removed, PropertyScoringService.ALGORITHM_VERSION);
    }
}
```

`ApplicationReadyEvent`, не `@PostConstruct` — на момент `@PostConstruct` транзакционный прокси ещё не обёрнут, `@Modifying`-запрос упал бы с `TransactionRequiredException`.

---

## 4.6. `PropertyService` — CRUD и лендинг

[`PropertyService.java`](../backend/src/main/java/com/example/backend/service/PropertyService.java)

### `getRecommendedPropertiesForTenant(tenantUserId)`

Главная точка входа для арендатора, открывшего «карту/список рекомендованных».

```java
@Transactional
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

- Если у арендатора есть **активный SearchProfile** — батч-скоринг через snapshot-кэш, сортировка по убыванию totalScore.
- Если профилей нет — просто все PUBLISHED без скоринга.

### `createProperty(landlordId, request)`

Создание объявления. Статус сразу `PUBLISHED`.

### `updateProperty` / `deleteProperty` — ownership + инвалидация

```java
@Transactional
public Property updateProperty(Long landlordId, Long propertyId, CreatePropertyRequest request) {
    Property property = propertyRepository.findById(propertyId)
            .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

    if (!property.getLandlord().getId().equals(landlordId)) {
        throw new RuntimeException("Нет прав на редактирование чужого объекта");
    }

    property.setTitle(request.getTitle());
    property.setDescription(request.getDescription());
    property.setPricePerMonth(request.getPricePerMonth());

    Property saved = propertyRepository.save(property);
    propertyScoreSnapshotService.invalidateByProperty(propertyId);
    return saved;
}

@Transactional
public void deleteProperty(Long landlordId, Long propertyId) {
    Property property = propertyRepository.findById(propertyId)
            .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

    if (!property.getLandlord().getId().equals(landlordId)) {
        throw new RuntimeException("Нет прав на удаление чужого объекта");
    }

    property.setStatus(PropertyStatus.ARCHIVED);  // soft-delete
    propertyRepository.save(property);
    propertyScoreSnapshotService.invalidateByProperty(propertyId);
}
```

- **Ownership-проверка**: только landlord-владелец может править.
- **Soft-delete**: `status = ARCHIVED`, реального DELETE нет.
- **Инвалидация snapshot'ов** — арендаторы при следующем открытии увидят актуальную оценку.

### Избранное

```java
@Transactional
public void addFavorite(Long tenantId, Long propertyId) {
    User user = userRepository.findById(tenantId).orElseThrow(...);
    Property property = propertyRepository.findById(propertyId).orElseThrow(...);

    if (user.getFavoriteProperties() == null) {
        user.setFavoriteProperties(new HashSet<>());
    }
    boolean added = user.getFavoriteProperties().add(property);
    userRepository.save(user);
    if (added) {
        analyticsService.logFavoriteEvent(propertyId, tenantId);  // только при реальном добавлении
    }
}
```

`Set.add` возвращает `false` если элемент уже был — событие лога не пишется (идемпотентно).

### `scorePropertyForTenant`

Точечный скоринг помещения для арендатора. Используется при открытии карточки.

```java
@Transactional
public ScoredPropertyDto scorePropertyForTenant(Long tenantId, Long propertyId, Long profileId, boolean force) {
    SearchProfile profile = resolveProfile(tenantId, profileId);
    if (profile == null) return null;

    Property property = propertyRepository.findById(propertyId).orElseThrow(...);

    return propertyScoreSnapshotService.scoreWithSnapshot(profile, property, force);
}

private SearchProfile resolveProfile(Long tenantId, Long profileId) {
    if (profileId != null) {
        return searchProfileRepository.findById(profileId)
                .filter(p -> p.getTenant() != null && tenantId.equals(p.getTenant().getId()))
                .orElse(null);
    }
    var profiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantId);
    return profiles.isEmpty() ? null : profiles.get(0);
}
```

`resolveProfile` — либо явно указанный profileId (с проверкой ownership), либо первый активный профиль арендатора.

---

## 4.7. `SearchProfileService` — проекты поиска

[`SearchProfileService.java`](../backend/src/main/java/com/example/backend/service/SearchProfileService.java)

### CRUD

```java
@Transactional
public SearchProfile createSearchProfile(Long tenantId, CreateSearchProfileRequest request) {
    User tenant = userRepository.findById(tenantId).orElseThrow(...);
    SearchProfile profile = buildProfileFromRequest(request, tenant);
    return searchProfileRepository.save(profile);
}

@Transactional
public SearchProfile updateSearchProfile(Long tenantId, Long profileId, CreateSearchProfileRequest request) {
    SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);

    profile.setName(request.getName());
    // ... все остальные поля ...

    SearchProfile saved = searchProfileRepository.save(profile);
    // Критерии профиля изменились — все сохранённые оценки устарели.
    propertyScoreSnapshotService.invalidateByProfile(profileId);
    return saved;
}

@Transactional
public void deleteSearchProfile(Long tenantId, Long profileId) {
    SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);
    propertyScoreSnapshotService.invalidateByProfile(profileId);
    searchProfileRepository.delete(profile);
}
```

**Каждое изменение/удаление профиля инвалидирует все snapshot'ы под этот профиль** — арендатор сразу увидит оценки под новые критерии.

### `getScoredPropertiesForProfile` — батч-скоринг

```java
@Transactional
public List<ScoredPropertyDto> getScoredPropertiesForProfile(Long tenantId, Long profileId) {
    SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);
    var allPublished = propertyRepository.findByStatus(PropertyStatus.PUBLISHED);
    return propertyScoreSnapshotService.scoreBatchWithSnapshot(profile, allPublished, false);
}
```

В отличие от `getRecommendedPropertiesForTenant` (которая возвращает `List<Property>`), здесь возвращается **`List<ScoredPropertyDto>`** — с полной разбивкой по баллам. Используется на фронте, когда нужно показать «бейдж 75/100» и тултип в карточке списка.

### Ownership-helper

```java
private SearchProfile getProfileOwnedByTenant(Long tenantId, Long profileId) {
    SearchProfile profile = searchProfileRepository.findById(profileId)
            .orElseThrow(() -> new RuntimeException("Проект поиска не найден"));
    if (!profile.getTenant().getId().equals(tenantId)) {
        throw new RuntimeException("Нет прав доступа к этому проекту поиска");
    }
    return profile;
}
```

Используется во всех мутациях.

---

## 4.8. `OpenRouterAiService` — AI-объяснение скоринга

[`OpenRouterAiService.java`](../backend/src/main/java/com/example/backend/service/OpenRouterAiService.java)

Опциональный сервис: даёт арендатору **человекочитаемое объяснение** оценки на русском языке, разбитое на 6 структурированных блоков.

### Каскад моделей

```java
private static final List<String> MODEL_FALLBACK_CHAIN = List.of(
        "meta-llama/llama-3.3-70b-instruct:free",
        "qwen/qwen3-next-80b-a3b-instruct:free",
        "z-ai/glm-4.5-air:free"
);
private static final int MAX_TOKENS = 900;
```

OpenRouter принимает массив `models` (до 3 элементов — ограничение API) и сам переключает на следующую при 402/429/5xx. Llama 3.3 70B — приоритетная (лучшая связность на русском); GLM/Qwen — fallback с реально работающим free-tier.

### Жёсткий промпт

```java
private String buildUserPrompt(ScoredPropertyDto scored, SearchProfile profile) {
    String facts = buildFactsheet(scored, profile);

    return """
            Ты пишешь на русском языке развёрнутый блочный разбор оценки помещения.
            Тебе даны ФАКТЫ — пересказывай только их. ИНЫХ ФАКТОВ НЕТ.

            ЖЁСТКАЯ СТРУКТУРА ОТВЕТА — РОВНО ЭТИ 6 БЛОКОВ:

            ФИНАНСЫ
            <1–2 предложения... Балл X/20.>

            ТЕХНИКА
            <Балл X/20.>

            КОНКУРЕНТЫ
            <Конкретные имена по правилу ниже... Балл X/40.>

            СИНЕРГИЯ
            <Балл X/15.>

            ТРАНСПОРТ
            <Балл X/5.>

            ИТОГ
            <N/100, главное ограничение — ...>

            ЖЁСТКИЕ ПРАВИЛА:
            - Заголовки блоков — РОВНО как выше...
            - Конкурентов упоминай ПОИМЁННО:
                • если прямых ≤ 5 — назови КАЖДОГО;
                • 6–15 — назови первые 5 и допиши «и ещё N»;
                • ≥ 16 — назови первые 3 и допиши «и ещё N».
            ...

            ФАКТЫ:
            %s

            Теперь напиши разбор...
            """.formatted(facts);
}
```

**Особенности промпта:**

1. **Жёсткая структура** из 6 блоков с прописанным форматом заголовка и количеством предложений.
2. **Полный пример** в промпте на других данных — few-shot learning.
3. **Запрет на «выдумывание»** — только факты из секции FACTS.
4. **Правила перечисления конкурентов** — чтобы LLM не писала размытое «несколько аптек».

### Factsheet — структурированный ввод

```java
private String buildFactsheet(ScoredPropertyDto scored, SearchProfile profile) {
    StringBuilder sb = new StringBuilder();

    sb.append("Адрес: ").append(p.getAddress()).append('\n');
    sb.append("Параметры помещения: ").append(p.getAreaSqm()).append(" м², ")
      .append(p.getPricePerMonth()).append(" ₽/мес, ")
      .append(p.getPowerKw()).append(" кВт, потолки ").append(p.getCeilingHeight()).append(" м, ")
      .append("ремонт — ").append(translateRepair(p.getRepairState())).append(".\n");

    sb.append("\nФИНАНСЫ ").append(scored.getFinancialScore()).append("/20:\n");
    sb.append(buildFinancialBreakdown(p, profile));

    sb.append("\nТЕХНИКА ").append(scored.getTechnicalScore()).append("/20:\n");
    sb.append(buildTechnicalBreakdown(p, profile));

    sb.append("\nКОНКУРЕНТЫ ").append(scored.getCompetitorScore()).append("/40:\n");
    sb.append(buildCompetitorBreakdown(scored));

    sb.append("\nСИНЕРГИЯ С СОСЕДЯМИ ").append(scored.getSynergyScore()).append("/15:\n");
    sb.append(buildSynergyBreakdown(scored, profile));

    sb.append("\nТРАНСПОРТ ").append(scored.getTransportScore()).append("/5:\n");
    sb.append(buildTransportBreakdown(scored));

    sb.append("\nИТОГ: ").append(scored.getTotalScore()).append("/100 (")
      .append(scored.getMatchLabel()).append(").");
    return sb.toString();
}
```

Перед LLM мы сами **разложили данные на блоки** и подсказали ей балл за каждый компонент. LLM остаётся только пересказать в человеческой форме.

### Безымянные POI

```java
private boolean isUnnamedPlaceholder(String name) {
    return name.matches("^(shop|amenity|office|healthcare|leisure|craft|tourism)=.+");
}
```

Если в OSM нет тега `name`, мы кладём имя как `"amenity=pharmacy"`. Промпт ловит такие плейсхолдеры и отдельно говорит LLM «и ещё N без названия» — чтобы не было нелепого «конкурент: amenity=pharmacy».

### Fallback

```java
private ScoreExplainResponse fallback() {
    return new ScoreExplainResponse("AI-анализ временно недоступен. Оценку можно интерпретировать по шкале баллов самостоятельно.");
}
```

При любом сбое (отсутствие ключа, 5xx от OpenRouter, пустой ответ) — мягкая заглушка вместо exception. Скоринг сам по себе работает без AI.

---

## 4.9. `ApplicationService` — заявки

[`ApplicationService.java`](../backend/src/main/java/com/example/backend/service/ApplicationService.java)

### `createApplication`

```java
@Transactional
public ApplicationResponseDto createApplication(Long tenantId, Long propertyId, String coverLetter) {
    User tenant = userRepository.findById(tenantId).orElseThrow(...);
    Property property = propertyRepository.findById(propertyId).orElseThrow(...);

    if (property.getStatus() != PropertyStatus.PUBLISHED) {
        throw new RuntimeException("Помещение недоступно для аренды");
    }

    Application application = Application.builder()
            .tenant(tenant)
            .property(property)
            .status(ApplicationStatus.PENDING)
            .coverLetter(coverLetter)
            .build();

    Application saved = applicationRepository.save(application);
    notificationService.sendPushNotification(property.getLandlord().getId(),
            "Новая заявка", "Поступила новая заявка на помещение: " + property.getTitle());
    return mapToDto(saved);
}
```

- Заявка возможна только на `PUBLISHED`-помещение.
- Push арендодателю.

### `updateApplicationStatus` — landlord-side

```java
@Transactional
public ApplicationResponseDto updateApplicationStatus(Long landlordId, Long applicationId,
                                                      ApplicationStatus newStatus, String rejectionReason) {
    Application application = applicationRepository.findById(applicationId).orElseThrow(...);

    // Проверка ownership
    if (!application.getProperty().getLandlord().getId().equals(landlordId)) {
        throw new RuntimeException("У вас нет прав на изменение этой заявки");
    }

    application.setStatus(newStatus);

    if (newStatus == ApplicationStatus.REJECTED && rejectionReason != null && !rejectionReason.isEmpty()) {
        application.setRejectionReason(rejectionReason);
    }

    if (newStatus == ApplicationStatus.ACCEPTED) {
        Property property = application.getProperty();
        property.setStatus(PropertyStatus.RENTED);
        propertyRepository.save(property);
    }

    Application saved = applicationRepository.save(application);
    notificationService.sendPushNotification(application.getTenant().getId(),
            "Статус заявки обновлен", "Ваша заявка перешла в статус: " + newStatus);
    return mapToDto(saved);
}
```

**Эффекты при `ACCEPTED`:**
- `Property.status = RENTED` — помещение исчезает из листинга арендаторов.
- Push арендатору.

**При `REJECTED`** — обязательно прокидывается `rejectionReason` для UX (арендатор видит причину).

### `deleteApplication` — обе стороны

```java
@Transactional
public void deleteApplication(Long currentUserId, Long applicationId) {
    Application application = applicationRepository.findById(applicationId).orElseThrow(...);

    boolean isTenant = application.getTenant().getId().equals(currentUserId);
    boolean isLandlord = application.getProperty().getLandlord().getId().equals(currentUserId);

    if (!isTenant && !isLandlord) {
        throw new RuntimeException("Вы не можете удалить эту заявку");
    }

    if (application.getStatus() == ApplicationStatus.ACCEPTED) {
        throw new RuntimeException("Нельзя удалить уже принятую заявку");
    }

    applicationRepository.delete(application);
}
```

- Удалить может **любая** из сторон.
- **Нельзя** удалить `ACCEPTED` — она привязана к реальной аренде.

### `getApplicationById` — ownership по роли

```java
@Transactional(readOnly = true)
public ApplicationResponseDto getApplicationById(Long applicationId, Long currentUserId, Role currentUserRole) {
    Application application = applicationRepository.findById(applicationId).orElseThrow(...);

    if (currentUserRole == Role.TENANT && !application.getTenant().getId().equals(currentUserId)) {
        throw new RuntimeException("Доступ запрещен. Это не ваша заявка.");
    }
    if (currentUserRole == Role.LANDLORD && !application.getProperty().getLandlord().getId().equals(currentUserId)) {
        throw new RuntimeException("Доступ запрещен. Это заявка не на ваше помещение.");
    }

    return mapToDto(application);
}
```

Контракт: TENANT видит только свои заявки, LANDLORD — только на свои помещения.

### `mapToDto` — устойчивость к удалённому property

Маппинг `Application` → `ApplicationResponseDto` устойчив к отсутствию полей: если property удалено, tenant не имеет профиля и т.д. — подставляются дефолты вроде `"Объект удален"`, `"Не указано"`. Это позволяет не падать в UI при разрушенных связях.

---

## 4.10. `ChatService` — чат-комнаты и сообщения

[`ChatService.java`](../backend/src/main/java/com/example/backend/service/ChatService.java)

### `getOrCreateChatRoom`

```java
@Transactional
public ChatRoomDto getOrCreateChatRoom(Long applicationId) {
    ChatRoom chatRoom = chatRoomRepository.findByApplicationId(applicationId)
            .orElseGet(() -> createChatRoom(applicationId));
    return mapToChatRoomDto(chatRoom);
}

private ChatRoom createChatRoom(Long applicationId) {
    Application application = applicationRepository.findById(applicationId)
            .orElseThrow(() -> new RuntimeException("Application not found"));

    ChatRoom chatRoom = ChatRoom.builder()
            .application(application)
            .landlord(application.getProperty().getLandlord())
            .tenant(application.getTenant())
            .build();
    return chatRoomRepository.save(chatRoom);
}
```

Чат-комнаты создаются ленив**ы**м образом — при первом открытии чата по заявке. Одна заявка = одна комната.

### `saveMessage` — сохранение + push

```java
@Transactional
public ChatMessageDto saveMessage(Long roomId, Long senderId, String content) {
    ChatRoom chatRoom = chatRoomRepository.findById(roomId).orElseThrow(...);
    User sender = userRepository.findById(senderId).orElseThrow(...);

    ChatMessage message = ChatMessage.builder()
            .chatRoom(chatRoom)
            .sender(sender)
            .content(content)
            .isRead(false)
            .build();

    ChatMessage savedMessage = chatMessageRepository.save(message);

    Long recipientId = chatRoom.getLandlord().getId().equals(senderId)
            ? chatRoom.getTenant().getId()
            : chatRoom.getLandlord().getId();
    notificationService.sendPushNotification(recipientId, "Новое сообщение",
            "От " + sender.getEmail() + ": " + content);

    return mapToChatMessageDto(savedMessage);
}
```

После сохранения — push получателю (тот, кто **не** отправитель).

**Real-time delivery** идёт через STOMP в `ChatController` (см. `WebSocketConfig` в [01-architecture-and-infrastructure.md §1.7.3](01-architecture-and-infrastructure.md)) — `saveMessage` вызывается из обоих путей: REST POST и `@MessageMapping`. Получатели слушают `/topic/chat/{roomId}` и получают live-обновления.

---

## 4.11. `NotificationService` — push (заглушка)

[`NotificationService.java`](../backend/src/main/java/com/example/backend/service/NotificationService.java)

```java
@Service
@Slf4j
public class NotificationService {

    public void sendPushNotification(Long userId, String title, String body) {
        // Заглушка для отправки Push-уведомлений через Firebase Cloud Messaging (FCM)
        // В будущем здесь будет интеграция с com.google.firebase.messaging.FirebaseMessaging
        log.info("🔔 [PUSH NOTIFICATION] To User ID: {} | Title: {} | Body: {}", userId, title, body);
    }
}
```

**Текущее состояние:** только логирование. FCM не интегрирован. Real-time доставка сообщений в чате идёт через WebSocket; push нужен только для напоминаний, когда приложение закрыто — пока не реализовано.

Места, где push вызывается:
- `ApplicationService.createApplication` → landlord'у.
- `ApplicationService.updateApplicationStatus` → tenant'у.
- `ChatService.saveMessage` → собеседнику.

---

## 4.12. `AnalyticsService` — события и аналитика

[`AnalyticsService.java`](../backend/src/main/java/com/example/backend/service/AnalyticsService.java)

### Логирование событий

```java
public void logPropertyView(Long propertyId, Long viewerId) {
    Property property = propertyRepository.findById(propertyId).orElse(null);
    if (property == null) return;

    User viewer = null;
    if (viewerId != null) {
        viewer = userRepository.findById(viewerId).orElse(null);
    }

    PropertyViewEvent event = PropertyViewEvent.builder()
            .property(property)
            .viewer(viewer)
            .build();
    propertyViewEventRepository.save(event);
}

public void logFavoriteEvent(Long propertyId, Long tenantId) {
    // симметрично
}
```

Вызывается из `PropertyController.getProperty` (просмотры) и `PropertyService.addFavorite` (избранное).

### `getLandlordAnalytics(landlordId)` — за 30 дней

```java
public AnalyticsDto getLandlordAnalytics(Long landlordId) {
    LocalDateTime thirtyDaysAgo = LocalDateTime.now().minusDays(30);

    List<PropertyViewEvent> recentViews = dedupeViewsByViewer(propertyViewEventRepository
            .findByPropertyLandlordIdAndViewTimestampAfter(landlordId, thirtyDaysAgo)
            .stream()
            .filter(e -> isNotArchived(e.getProperty()))
            .collect(Collectors.toList()));

    List<FavoriteEvent> recentFavorites = favoriteEventRepository
            .findByPropertyLandlordIdAndCreatedAtAfter(landlordId, thirtyDaysAgo)
            .stream()
            .filter(e -> isNotArchived(e.getProperty()))
            .collect(Collectors.toList());

    List<Application> recentApps = applicationRepository
            .findByProperty_LandlordIdAndCreatedAtAfter(landlordId, thirtyDaysAgo)
            .stream()
            .filter(a -> isNotArchived(a.getProperty()))
            .collect(Collectors.toList());

    // Все заявки за всё время (по неархивным помещениям)
    List<Property> activeProperties = propertyRepository.findByLandlordId(landlordId).stream()
            .filter(this::isNotArchived).collect(Collectors.toList());
    long totalApplications = 0;
    for (Property p : activeProperties) {
        totalApplications += applicationRepository.findByPropertyId(p.getId()).size();
    }

    long totalUniqueMessengers = chatRoomRepository.countDistinctTenantsByLandlordId(landlordId);

    return AnalyticsDto.builder()
            .totalViewsLast30Days(recentViews.size())
            .totalFavoritesLast30Days(recentFavorites.size())
            .totalApplications(totalApplications)
            .totalApplicationsLast30Days(recentApps.size())
            .totalUniqueMessengers(totalUniqueMessengers)
            .viewsByDate(groupViewsByDate(recentViews))
            .favoritesByDate(groupFavoritesByDate(recentFavorites))
            .applicationsByDate(groupApplicationsByDate(recentApps))
            .build();
}
```

**Что возвращает:**
- 30-дневные счётчики просмотров, избранного, заявок.
- Всего заявок (вне зависимости от времени) по неархивным помещениям.
- Уникальные «собеседники» — кто завёл с тобой чат.
- Гистограммы по датам — для графика на фронте.

### Дедупликация просмотров

```java
private List<PropertyViewEvent> dedupeViewsByViewer(List<PropertyViewEvent> events) {
    List<PropertyViewEvent> sorted = events.stream()
            .sorted(Comparator.comparing(
                    PropertyViewEvent::getViewTimestamp,
                    Comparator.nullsLast(Comparator.naturalOrder())))
            .collect(Collectors.toList());
    Set<String> seenPairs = new HashSet<>();
    List<PropertyViewEvent> result = new ArrayList<>(sorted.size());
    for (PropertyViewEvent e : sorted) {
        if (e.getProperty() == null) continue;
        if (e.getViewer() == null) {
            result.add(e);  // анонимные считаются отдельно
            continue;
        }
        String key = e.getProperty().getId() + ":" + e.getViewer().getId();
        if (seenPairs.add(key)) {
            result.add(e);
        }
    }
    return result;
}
```

Один авторизованный пользователь × одно помещение = один просмотр в аналитике, даже если он 50 раз открывал карточку. Анонимные (без JWT) события не группируются — нечем (нет userId).

### `isOwner`

```java
public boolean isOwner(Long propertyId, Long landlordId) {
    return propertyRepository.findById(propertyId)
            .map(p -> p.getLandlord() != null && landlordId.equals(p.getLandlord().getId()))
            .orElse(false);
}
```

Используется контроллером для проверки прав перед отдачей аналитики по конкретному помещению.

---

## 4.13. `FavoriteService` — альтернативный путь избранного

[`FavoriteService.java`](../backend/src/main/java/com/example/backend/service/FavoriteService.java)

```java
@Transactional
public void addFavorite(Long tenantId, Long propertyId) {
    User user = userRepository.findById(tenantId).orElseThrow(...);
    Property property = propertyRepository.findById(propertyId).orElseThrow(...);
    user.getFavoriteProperties().add(property);
    userRepository.save(user);
    analyticsService.logFavoriteEvent(propertyId, tenantId);
}

@Transactional(readOnly = true)
public List<Property> getFavorites(Long tenantId) {
    return propertyRepository.findFavoritePropertiesByTenantId(tenantId);
}
```

**Замечание:** функционально дублирует `PropertyService.addFavorite` / `getFavorites`. Существует исторически — на текущий момент `PropertyController.toggleFavorite` использует `PropertyService`. `FavoriteService` остаётся как отдельный entry-point, привязанный к `FavoriteController` (если такой регистрируется через `@ControllerAdvice` или вручную). При рефакторинге следует консолидировать.

Принципиальное отличие: `FavoriteService.addFavorite` **не проверяет** `added`-флаг, поэтому событие пишется каждый раз, даже при повторном добавлении. `PropertyService.addFavorite` пишет событие только при первом — это корректнее.

---

## 4.14. `ProfileService` — профили пользователей и аватары

[`ProfileService.java`](../backend/src/main/java/com/example/backend/service/ProfileService.java)

### Чтение

```java
@Transactional(readOnly = true)
public TenantProfile getTenantProfile(Long userId) {
    TenantProfile profile = tenantProfileRepository.findById(userId).orElseThrow(...);
    userRepository.findById(userId).ifPresent(u -> profile.setAvatarUrl(u.getAvatarUrl()));
    return profile;
}
```

`avatarUrl` живёт в `users.avatar_url`, но логически принадлежит профилю. При чтении подставляется в `@Transient` поле.

### Аватары

```java
@Transactional
public String uploadAvatar(Long userId, MultipartFile file) {
    User user = userRepository.findById(userId).orElseThrow(...);

    String oldUrl = user.getAvatarUrl();
    String newUrl = fileStorageService.store(file, "avatars/" + userId);
    user.setAvatarUrl(newUrl);
    userRepository.save(user);

    if (oldUrl != null) {
        fileStorageService.delete(oldUrl);  // подчищаем за собой
    }
    return newUrl;
}

@Transactional
public void deleteAvatar(Long userId) {
    User user = userRepository.findById(userId).orElseThrow(...);
    if (user.getAvatarUrl() != null) {
        fileStorageService.delete(user.getAvatarUrl());
        user.setAvatarUrl(null);
        userRepository.save(user);
    }
}
```

При замене аватара старый файл удаляется с диска. Это важно: без удаления `./uploads/avatars/{userId}/` со временем накопит десятки осиротевших файлов.

---

## 4.15. `PropertyImageService` — фотографии помещений

[`PropertyImageService.java`](../backend/src/main/java/com/example/backend/service/PropertyImageService.java)

### Лимит и главное фото

```java
private static final int MAX_IMAGES_PER_PROPERTY = 10;

@Transactional
public List<PropertyImage> upload(Long landlordId, Long propertyId, List<MultipartFile> files) {
    Property property = loadOwned(landlordId, propertyId);

    List<PropertyImage> existing = imageRepository.findByPropertyId(propertyId);
    if (existing.size() + files.size() > MAX_IMAGES_PER_PROPERTY) {
        throw new IllegalArgumentException("Превышен лимит фотографий (" + MAX_IMAGES_PER_PROPERTY + ")");
    }

    boolean hasMain = existing.stream().anyMatch(i -> Boolean.TRUE.equals(i.getIsMain()));

    List<PropertyImage> saved = new ArrayList<>();
    for (MultipartFile file : files) {
        String url = fileStorageService.store(file, "properties/" + propertyId);
        PropertyImage image = PropertyImage.builder()
                .property(property)
                .imageUrl(url)
                .isMain(!hasMain && saved.isEmpty())  // первое загруженное при пустом property → main
                .build();
        saved.add(imageRepository.save(image));
        if (Boolean.TRUE.equals(image.getIsMain())) {
            hasMain = true;
        }
    }
    return saved;
}
```

**Логика главного фото при загрузке:**
- Если у помещения нет ни одного фото — первое загруженное становится главным.
- Если уже есть — новые загружаются как обычные.

### Удаление с переназначением main

```java
@Transactional
public void delete(Long landlordId, Long propertyId, Long imageId) {
    loadOwned(landlordId, propertyId);
    PropertyImage image = imageRepository.findById(imageId).orElseThrow(...);
    if (!image.getProperty().getId().equals(propertyId)) {
        throw new RuntimeException("Фото принадлежит другому объекту");
    }

    boolean wasMain = Boolean.TRUE.equals(image.getIsMain());
    fileStorageService.delete(image.getImageUrl());
    imageRepository.delete(image);

    if (wasMain) {
        imageRepository.findByPropertyId(propertyId).stream().findFirst().ifPresent(next -> {
            next.setIsMain(true);
            imageRepository.save(next);
        });
    }
}
```

Если удалили главное — следующее первое автоматически становится главным.

### Установка main

```java
@Transactional
public void setMain(Long landlordId, Long propertyId, Long imageId) {
    loadOwned(landlordId, propertyId);
    List<PropertyImage> images = imageRepository.findByPropertyId(propertyId);
    boolean found = false;
    for (PropertyImage image : images) {
        boolean shouldBeMain = image.getId().equals(imageId);
        if (shouldBeMain) found = true;
        image.setIsMain(shouldBeMain);
    }
    if (!found) {
        throw new RuntimeException("Фото не найдено");
    }
    imageRepository.saveAll(images);
}
```

Атомарно: все фото получают `isMain=false`, кроме одного. Гарантия consistency через single transactional save.

---

## 4.16. `FileStorageService` — работа с ФС

[`FileStorageService.java`](../backend/src/main/java/com/example/backend/service/FileStorageService.java)

### Валидация

```java
private static final Set<String> ALLOWED_MIME = Set.of(
        "image/jpeg", "image/jpg", "image/png", "image/webp"
);
private static final long MAX_BYTES = 5L * 1024 * 1024; // 5MB

private void validate(MultipartFile file) {
    if (file == null || file.isEmpty()) throw new IllegalArgumentException("Файл пустой");
    if (file.getSize() > MAX_BYTES) throw new IllegalArgumentException("Файл больше 5MB");
    String mime = file.getContentType();
    if (mime == null || !ALLOWED_MIME.contains(mime.toLowerCase())) {
        throw new IllegalArgumentException("Поддерживаются только JPEG/PNG/WebP");
    }
}
```

Только картинки, до 5MB.

### Сохранение

```java
public String store(MultipartFile file, String subdir) {
    validate(file);
    try {
        Path dir = root.resolve(subdir).normalize();
        if (!dir.startsWith(root)) {
            throw new IllegalArgumentException("Некорректный путь");
        }
        Files.createDirectories(dir);

        String ext = resolveExtension(file.getContentType(), file.getOriginalFilename());
        String name = UUID.randomUUID() + ext;
        Path target = dir.resolve(name);
        Files.copy(file.getInputStream(), target, StandardCopyOption.REPLACE_EXISTING);
        return "/uploads/" + subdir + "/" + name;
    } catch (IOException e) {
        throw new RuntimeException("Не удалось сохранить файл", e);
    }
}
```

**Безопасность:**
- `dir.startsWith(root)` — защита от path traversal: `subdir = "../../etc"` не выйдет за `root`.
- Имя файла — UUID, исходное имя пользователя не используется (защита от спецсимволов и коллизий).
- Расширение определяется по MIME-типу, не по `originalFilename`.

### Удаление

```java
public void delete(String publicUrl) {
    if (publicUrl == null || !publicUrl.startsWith("/uploads/")) return;
    try {
        String relative = publicUrl.substring("/uploads/".length());
        Path target = root.resolve(relative).normalize();
        if (target.startsWith(root)) {
            Files.deleteIfExists(target);
        }
    } catch (IOException e) {
        log.warn("Не удалось удалить файл {}: {}", publicUrl, e.getMessage());
    }
}
```

- Молча игнорирует если файла нет (`deleteIfExists`).
- Path-traversal-защита та же.
- Ошибки IO логируются, но не пробрасываются — удаление физического файла не должно ронять бизнес-операцию.

---

## 4.17. `CategoryService` — справочник категорий

[`CategoryService.java`](../backend/src/main/java/com/example/backend/service/CategoryService.java)

### Дерево

```java
@Transactional(readOnly = true)
public List<BusinessCategoryDto> getCategoryTree() {
    List<BusinessCategory> rootCategories = categoryRepository.findByParentCategoryIsNull();
    return rootCategories.stream()
            .map(this::mapToDto)
            .collect(Collectors.toList());
}

private BusinessCategoryDto mapToDto(BusinessCategory category) {
    BusinessCategoryDto dto = new BusinessCategoryDto();
    dto.setId(category.getId());
    dto.setName(category.getName());

    if (category.getSubCategories() != null && !category.getSubCategories().isEmpty()) {
        dto.setSubCategories(
                category.getSubCategories().stream()
                        .map(this::mapToDto)
                        .collect(Collectors.toList())
        );
    }
    return dto;
}
```

Рекурсивный маппинг сверху вниз: root → их subCategories → ... В текущей схеме глубина дерева — 2 уровня (root + leaves), но код готов к произвольной глубине.

### Плоский список

```java
@Transactional(readOnly = true)
public List<BusinessCategoryDto> getAllFlat() {
    return categoryRepository.findAll().stream()
            .map(category -> {
                BusinessCategoryDto dto = new BusinessCategoryDto();
                dto.setId(category.getId());
                dto.setName(category.getName());
                return dto;
            })
            .collect(Collectors.toList());
}
```

Без вложенности — для случаев, когда фронту проще искать по id без обхода дерева.

### CRUD категорий

`createCategory`, `updateCategory`, `deleteCategory` — стандартные операции. В текущей UI/API эти эндпоинты не используются для арендатор/арендодатель сценариев; они есть на случай админ-операций.

---

## 4.18. `InfrastructureService` — legacy POI-поиск

[`InfrastructureService.java`](../backend/src/main/java/com/example/backend/service/InfrastructureService.java)

```java
@Service
@Slf4j
public class InfrastructureService {

    private final RestTemplate restTemplate = new RestTemplate();

    public List<PoiDto> getInfrastructureNearby(double lat, double lon, int radius) {
        try {
            String overpassQuery = "[out:json];" +
                    "(" +
                    "node[\"station\"=\"subway\"](around:" + radius + "," + lat + "," + lon + ");" +
                    "node[\"amenity\"=\"cafe\"](around:" + radius + "," + lat + "," + lon + ");" +
                    "node[\"amenity\"=\"university\"](around:" + radius + "," + lat + "," + lon + ");" +
                    ");" +
                    "out body 15;";

            String url = "https://overpass-api.de/api/interpreter?data=" + overpassQuery;
            ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);
            // ... парсинг ...
        } catch (Exception e) {
            log.error("Error fetching POIs from Overpass API", e);
            pois.add(PoiDto.builder().name("Ближайшее метро (демо)").category("metro").distanceMeters(300).build());
        }
        pois.sort((p1, p2) -> Double.compare(p1.getDistanceMeters(), p2.getDistanceMeters()));
        return pois;
    }
}
```

**Замечание:** это **старый сервис**, который:
- Использует `RestTemplate` (deprecated в Spring 6 в пользу `RestClient`).
- Ходит **напрямую** в public `overpass-api.de` (а не через локальный mirror).
- Не имеет кэширования.
- Возвращает hardcoded заглушку «Ближайшее метро (демо)» при ошибке.

Используется только в `InfrastructureController` для простого POI-списка (метро/кафе/университеты) в карточке помещения. Скоринг и реальная аналитика идут через `OverpassPlacesService`. Подлежит рефакторингу: либо удалить и заменить вызовом `OverpassPlacesService.searchAreaSnapshot`, либо использовать тот же кэш.

---

## 4.19. Транзакционные границы и параллелизм

| Сервис                          | Транзакционность                                                                |
|---------------------------------|---------------------------------------------------------------------------------|
| `PropertyService`               | Большинство методов `@Transactional` (write) или `@Transactional(readOnly=true)` |
| `PropertyScoringService`        | **Не транзакционен.** Работает с уже загруженными entity, делает HTTP-запросы.  |
| `PropertyScoreSnapshotService`  | `@Transactional` — read+write snapshot'ов                                       |
| `OverpassPlacesService`         | Не транзакционен (Caffeine + delegate к `OverpassPersistentCache`)             |
| `OverpassPersistentCache`       | `@Transactional(readOnly=true)` на get, `@Transactional` на put и cleanup       |
| `SearchProfileService`          | `@Transactional` на мутации, `readOnly` на чтения                               |
| `ApplicationService`            | `@Transactional` на all-CUD + `(readOnly=true)` на гетеры                       |
| `ChatService`                   | `@Transactional` на `getOrCreateChatRoom` и `saveMessage`                       |
| `AnalyticsService`              | Без явных `@Transactional` — все методы read-only, JPA-методы атомарны          |
| `ProfileService`                | `@Transactional` для аватаров (важно: и user.save, и file.delete атомарны)      |
| `PropertyImageService`          | `@Transactional` для upload/delete/setMain                                      |
| `FileStorageService`            | Не транзакционен (ФС-операции)                                                  |

### Параллелизм в PropertyScoringService

Использует `ForkJoinPool(8)` с `parallelStream`. Перед параллельным проходом — принудительная инициализация всех lazy-ассоциаций, иначе в параллельных потоках Hibernate Session недоступен и улетит `LazyInitializationException`.

### Транзакционность и snapshot

`saveSnapshot` в `PropertyScoreSnapshotService` идёт внутри той же транзакции, что и `scoreWithSnapshot`. Если что-то упадёт после `scoringService.scorePropertyWithGis` — snapshot не сохранится. Это правильно: лучше пересчитать заново при следующем запросе, чем сохранить полу-битую запись.

`evictBroken` (удаление битого snapshot'а при ошибке десериализации) — `@Transactional(propagation=REQUIRES_NEW)`, чтобы не откатывалось вместе с основной транзакцией чтения.

---

## 4.20. Пути запросов (cheat-sheet)

### Открытие списка рекомендованных арендатором

```
GET /api/properties/recommended
   └→ PropertyController.getRecommended
      └→ PropertyService.getRecommendedPropertiesForTenant
         ├→ propertyRepository.findByStatus(PUBLISHED)
         ├→ searchProfileRepository.findByTenantIdAndIsActiveTrue
         └→ propertyScoreSnapshotService.scoreBatchWithSnapshot
            ├→ repository.findAllForBatch (один IN-запрос)
            └→ для непокрытых: PropertyScoringService.scoreAndRankProperties
                              └→ ForkJoinPool(8) × scoreInternal
                                 └→ OverpassPlacesService.searchAreaSnapshot
                                    ├→ L1 Caffeine
                                    ├→ L2 OverpassPersistentCache
                                    └→ HTTP к Overpass с retry
```

### Подача заявки

```
POST /api/applications {propertyId, coverLetter}
   └→ ApplicationController.create
      └→ ApplicationService.createApplication
         ├→ проверка status=PUBLISHED
         ├→ applicationRepository.save
         └→ notificationService.sendPushNotification(landlordId)
```

### Отправка сообщения

```
WS → /app/chat/{roomId}
   └→ ChatController @MessageMapping
      └→ ChatService.saveMessage
         ├→ chatMessageRepository.save
         ├→ notificationService.sendPushNotification(otherSide)
         └→ template.convertAndSend("/topic/chat/" + roomId, dto)  // broadcast
```

### AI-объяснение

```
GET /api/properties/{id}/explain
   └→ PropertyController.explainScore
      ├→ propertyScoringService.scorePropertyWithGis (с force=false → snapshot если есть)
      └→ openRouterAiService.explainScore
         ├→ buildFactsheet (структурированный ввод)
         ├→ buildUserPrompt (промпт с правилами и примером)
         ├→ POST openrouter/api/v1/chat/completions
         └→ fallback на заглушку при ошибке
```

---

## 4.21. Сводка по «фичам» через сервисы

| Фича                                              | Главные сервисы                                                         |
|---------------------------------------------------|-------------------------------------------------------------------------|
| **Регистрация и логин**                           | `AuthService`, `EmailService`, `JwtService` (см. [02-security](02-security-and-auth.md))    |
| **Каталог помещений + лента арендатора**          | `PropertyService`, `PropertyScoreSnapshotService`, `PropertyScoringService` |
| **Скоринг 0–100 баллов**                          | `PropertyScoringService` + `OverpassPlacesService`                      |
| **Кэширование Overpass**                          | `OverpassPlacesService` (Caffeine) + `OverpassPersistentCache` (DB)     |
| **Кэширование скоринга**                          | `PropertyScoreSnapshotService`                                          |
| **Проекты поиска**                                | `SearchProfileService` + инвалидация снимков                            |
| **AI-объяснение**                                 | `OpenRouterAiService` + builder промпта и факт-листа                    |
| **Заявки**                                        | `ApplicationService` + push через `NotificationService`                 |
| **Чат (REST+WS)**                                 | `ChatService` + STOMP-broker из `WebSocketConfig`                       |
| **Аналитика landlord'a**                          | `AnalyticsService` (события + дедуп + агрегация)                        |
| **Избранное**                                     | `PropertyService.addFavorite` (+ `FavoriteService` legacy)              |
| **Профили и аватары**                             | `ProfileService` + `FileStorageService`                                 |
| **Фото помещений**                                | `PropertyImageService` + `FileStorageService`                           |
| **Справочник категорий**                          | `CategoryService` + `DataInitializer` (init)                            |
| **POI вокруг (для карточки)**                     | `InfrastructureService` (legacy, требует рефакторинга)                  |

---

## 4.22. Известные ограничения сервисного слоя

1. **`NotificationService` — заглушка.** FCM не интегрирован. Push видны только в логе.
2. **`InfrastructureService` — устаревший.** Использует RestTemplate и public Overpass без кэша.
3. **`FavoriteService` дублирует `PropertyService.addFavorite`** — кандидат на консолидацию.
4. **AI-объяснение не кэшируется.** Каждый запрос — новый вызов OpenRouter (быстрый, но платит за токены).
5. **Параллельный скоринг ограничен 8 потоками.** Для одновременного скоринга от нескольких арендаторов общий backpressure не реализован.
6. **`scoreInternal` не throw'ит при отсутствии coords у property** — возвращает пустой OK-снимок и обнуляет геокомпоненты. Это корректно, но скрывает баги ввода данных.
7. **Снимки L3 без TTL-cleanup'а.** Растут со временем, хоть и медленно (один snapshot на (property, profile)).
8. **Email-отправка синхронная.** Сбой SMTP роняет `register`. Стоит асинхронная очередь.
