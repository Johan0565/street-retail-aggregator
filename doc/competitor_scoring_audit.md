# Аудит логики конкурентного скоринга — Street Retail Aggregator

> **Дата:** 2026-04-30  
> **Статус:** 🔴 Критический баг — конкурентный скор всегда 50 (0 конкурентов)  
> **Симптом:** Фронтенд (Overpass API) показывает кафе «Северянин», «Чайхана Дамаск» и т.д., но скоринг (2GIS API) выдаёт `direct=0, indirect=0`.

---

## 1. Поток данных конкурентного скоринга

### 1.1 Точка входа

Скоринг вызывается двумя способами:

**а) Массовый скоринг (экран рекомендаций):**
```
Controller → PropertyService → PropertyScoringService.scoreAndRankProperties()
```

**б) Одиночный скоринг (карточка объекта):**
```
Controller → PropertyScoringService.scorePropertyWithGis()
```

Оба метода загружают **все** категории из БД и делегируют в `scoreInternal()`:

```java
// PropertyScoringService.java:45-51
public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
    List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
    return properties.stream()
            .map(p -> scoreInternal(profile, p, allCategories))
            .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
            .collect(Collectors.toList());
}

// PropertyScoringService.java:56-59
public ScoredPropertyDto scorePropertyWithGis(SearchProfile profile, Property property) {
    List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
    return scoreInternal(profile, property, allCategories);
}
```

### 1.2 Единый внутренний scorer — `scoreInternal()`

```java
// PropertyScoringService.java:65-84
private ScoredPropertyDto scoreInternal(SearchProfile profile, Property property,
                                         List<BusinessCategory> allCategories) {
    int financial   = calculateFinancialScore(profile, property);   // 0-30
    int technical   = calculateTechnicalScore(profile, property);   // 0-20
    int competitors = calculateCompetitorScore(profile, property, allCategories); // 0-50
    int total       = financial + technical + competitors;

    log.debug("Scoring [{}]: total={}, fin={}, tech={}, comp={}",
            property.getId(), total, financial, technical, competitors);

    return ScoredPropertyDto.builder()
            .property(property)
            .totalScore(total)
            .financialScore(financial)
            .technicalScore(technical)
            .competitorScore(competitors)
            .matchLabel(resolveMatchLabel(total))
            .matchColor(resolveMatchColor(total))
            .build();
}
```

### 1.3 Пошаговый flow `calculateCompetitorScore()`

```
1. Проверка: есть ли businessCategory в профиле + координаты у Property
   └─ Если нет → return 50 (MAX_COMPETITOR_SCORE) ← РАННИЙ ВЫХОД!

2. Определение радиуса:
   └─ profile.searchRadiusMeters ?? 1000, но не более 5000

3. Запрос в 2GIS:
   └─ gisSearchService.getNearbyRubricNames(lat, lon, radius)
   └─ Возвращает List<List<String>> — рубрики каждого заведения

4. Если список пустой → return 50 ← ЕЩЁ ОДИН РАННИЙ ВЫХОД!

5. Цикл по заведениям:
   └─ Для каждого заведения — цикл по его рубрикам
      └─ matchRubricToCategory(rubric, allCategories)
         └─ Если matched.id == target.id → isDirect = true
         └─ Если matched.parentId == target.parentId → isIndirect = true

6. Подсчёт баллов по таблице direct/indirect
```

**Критический момент:** если `getNearbyRubricNames()` возвращает пустой список (ошибка API, неверный ключ, неверные координаты), скоринг молча возвращает **50 баллов** — как будто конкурентов нет.

---

## 2. Логика запроса в 2GIS API (GisSearchService.java)

### 2.1 Формирование URL

```java
// GisSearchService.java:48-54
String url = GIS_API_BASE
        + "?point=" + lon + "," + lat      // ← ПОРЯДОК: lon,lat (правильный для 2GIS!)
        + "&radius=" + radius
        + "&type=branch"
        + "&fields=items.rubrics"
        + "&key=" + apiKey
        + "&page_size=" + PAGE_SIZE;        // PAGE_SIZE = 50
```

**Итоговый URL:**
```
https://catalog.api.2gis.com/3.0/items?point={lon},{lat}&radius={radius}&type=branch&fields=items.rubrics&key={apiKey}&page_size=50
```

**Параметры:**

| Параметр | Значение | Комментарий |
|----------|----------|-------------|
| `point` | `{lon},{lat}` | **Порядок lon,lat** — это правильно для 2GIS |
| `radius` | `min(searchRadiusMeters, 5000)`, default `1000` | Метры |
| `type` | `branch` | Только филиалы/заведения |
| `fields` | `items.rubrics` | Запрашиваем рубрики |
| `key` | из `application.properties` | `4864f04f-8983-435a-ae2e-06ed696ed550` |
| `page_size` | `50` | ⚠️ **Только первые 50 заведений, пагинация НЕ реализована!** |

### 2.2 Передача координат — проверка бага lat/lon vs lon/lat

Вызов из `calculateCompetitorScore()`:
```java
// PropertyScoringService.java:191-194
List<List<String>> nearbyBusinesses = gisSearchService.getNearbyRubricNames(
        property.getLatitude().doubleValue(),   // 1-й аргумент = lat
        property.getLongitude().doubleValue(),   // 2-й аргумент = lon
        radius);
```

Сигнатура метода:
```java
// GisSearchService.java:46
public List<List<String>> getNearbyRubricNames(double lat, double lon, int radiusMeters)
```

Формирование URL:
```java
// GisSearchService.java:49
"?point=" + lon + "," + lat
```

✅ **Координаты передаются корректно:** `lat` и `lon` правильно местами в URL (`lon,lat` — формат 2GIS). Баг здесь **не подтверждён**.

### 2.3 Формирование кэш-ключа

```java
// GisSearchService.java:42-45
@Cacheable(
        value = "gisNearby",
        key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + #radiusMeters"
)
```

- Координаты округляются до 3-го знака (**~111 метров** точность)
- Формат ключа: `"55935_37629_1000"`
- TTL: **30 минут** (CacheConfig: `Caffeine.expireAfterWrite(30, MINUTES)`)

⚠️ **Побочный эффект кэша:** если первый запрос вернул пустой список (API-ошибка), результат кэшируется на 30 минут, и повторные запросы тоже получат пустоту.

### 2.4 Обработка ответа 2GIS

```java
// GisSearchService.java:75-103
private List<List<String>> parseRubricNames(String json) {
    try {
        JsonNode root = objectMapper.readTree(json);
        JsonNode items = root.path("result").path("items");

        List<List<String>> perItemRubrics = new ArrayList<>();
        if (items.isArray()) {
            for (JsonNode item : items) {
                JsonNode rubrics = item.path("rubrics");
                List<String> itemRubricNames = new ArrayList<>();
                if (rubrics.isArray()) {
                    for (JsonNode rubric : rubrics) {
                        String name = rubric.path("name").asText("").trim();
                        if (!name.isEmpty()) {
                            itemRubricNames.add(name.toLowerCase()); // ← toLowerCase() здесь!
                        }
                    }
                }
                if (!itemRubricNames.isEmpty()) {
                    perItemRubrics.add(itemRubricNames);
                }
            }
        }
        return perItemRubrics;
    } catch (Exception e) {
        log.warn("Ошибка парсинга ответа 2GIS: {}", e.getMessage());
        return List.of(); // ← Пустой список при ошибке!
    }
}
```

**Обработка ошибок:**
- Если HTTP-запрос упал → catch в `getNearbyRubricNames()` → `return List.of()` + warn-лог
- Если JSON невалидный → catch в `parseRubricNames()` → `return List.of()` + warn-лог
- В обоих случаях скоринг получает пустой список → **возвращает 50 баллов** (ложное «нет конкурентов»)

---

## 3. Алгоритм матчинга рубрик (BusinessCategory + PropertyScoringService)

### 3.1 Справочник категорий (DataInitializer.java)

Для категории **«Кафе»** заданы ключевые слова:

```java
// DataInitializer.java:41-42
findOrCreate("Кафе", food,
        "кафе,бистро,столовая,кафетерий");
```

Родительская категория: **«Еда и напитки»** (без собственных ключевых слов — `twoGisKeywords = null`).

Соседние подкатегории (siblings) — тот же parent «Еда и напитки»:

| Категория | twoGisKeywords |
|-----------|----------------|
| Продуктовый магазин | `продуктовый магазин,супермаркет,гастроном,...` |
| Кофейня | `кофейня,кофе,coffee shop,кофе-бар` |
| Ресторан | `ресторан,restaurant` |
| **Кафе** | **`кафе,бистро,столовая,кафетерий`** |
| Пекарня | `пекарня,булочная,...` |
| Кондитерская | `кондитерская,торты на заказ,...` |
| Фастфуд | `фастфуд,быстрое питание,бургер,...` |
| Бар | `паб,пивной бар,коктейльный бар,ночной клуб,бар ` |

### 3.2 Ядро матчинга — `matchRubricToCategory()`

Это **самый критический** метод. Вот его код полностью:

```java
// PropertyScoringService.java:251-272
private BusinessCategory matchRubricToCategory(String rubricName, List<BusinessCategory> categories) {
    String lowerRubric = rubricName.toLowerCase();
    Set<String> rubricWords = new HashSet<>(
            Arrays.asList(lowerRubric.replaceAll("[^а-яёa-z0-9\\s]", " ").trim().split("\\s+"))
    );

    for (BusinessCategory cat : categories) {
        if (cat.getTwoGisKeywords() == null || cat.getTwoGisKeywords().isBlank()) continue;

        for (String kw : cat.getTwoGisKeywords().toLowerCase().split(",")) {
            kw = kw.trim();
            if (kw.isEmpty()) continue;

            boolean matches = kw.contains(" ")
                    ? lowerRubric.contains(kw)        // многословный → substring
                    : rubricWords.contains(kw);        // однословный → exact word match

            if (matches) return cat;
        }
    }
    return null;
}
```

### 3.3 Два режима матчинга

**Однословные ключевые слова** (нет пробела) → **точное совпадение слова:**
- Рубрика разбивается на отдельные слова через regex `[^а-яёa-z0-9\\s]` → `split("\\s+")`
- Ключевое слово ищется среди множества слов (`Set.contains()`)
- Это предотвращает ложные срабатывания типа `"бар"` → `"барбершоп"`

**Многословные ключевые слова** (есть пробел) → **подстрока (substring):**
- Проверяется `lowerRubric.contains(kw)`
- Пример: `"кофе-бар"` → ключ `"кофе бар"` не сработает, т.к. в рубрике это `"кофе-бар"`, а после toLowerCase/trim пробел не появляется

### 3.4 Разделение на прямых и косвенных конкурентов

```java
// PropertyScoringService.java:200-230
BusinessCategory target = profile.getBusinessCategory();  // целевая категория (напр. "Кафе")
Long targetParentId = target.getParentCategory() != null
        ? target.getParentCategory().getId()
        : null;                                           // ID родителя (напр. ID "Еда и напитки")

for (List<String> businessRubrics : nearbyBusinesses) {
    boolean isDirect   = false;
    boolean isIndirect = false;

    for (String rubric : businessRubrics) {
        BusinessCategory matched = matchRubricToCategory(rubric, allCategories);
        if (matched == null) continue;

        // ПРЯМОЙ: matched.id совпадает с target.id
        if (matched.getId().equals(target.getId())) {
            isDirect = true;
            break;
        }
        // КОСВЕННЫЙ: matched имеет того же родителя, что и target
        if (targetParentId != null
                && matched.getParentCategory() != null
                && matched.getParentCategory().getId().equals(targetParentId)) {
            isIndirect = true;
        }
    }

    if (isDirect)        direct++;
    else if (isIndirect) indirect++;
}
```

**Прямой конкурент:** рубрика заведения сматчилась на ту же категорию, что указана в SearchProfile (например, `matchRubricToCategory("кафе", ...) → BusinessCategory("Кафе")`, и `target = "Кафе"`).

**Косвенный конкурент:** рубрика сматчилась на другую подкатегорию с тем же родителем (например, рубрика `"ресторан"` → категория `"Ресторан"`, parent = `"Еда и напитки"` = тот же parent, что у `"Кафе"`).

### 3.5 Таблица скоринга

```java
// PropertyScoringService.java:235-243
if (direct >= 5) return 0;
if (direct >= 3) return 5;
if (direct == 2) return 10;
if (direct == 1) return 20;
if (indirect >= 6) return 20;
if (indirect >= 3) return 30;
if (indirect >= 1) return 40;
return MAX_COMPETITOR_SCORE; // 50
```

---

## 4. Возможные причины сбоя (Гипотезы)

### Гипотеза 1: 🔴 2GIS API возвращает пустой ответ (невалидный ключ / лимит исчерпан)

**Вероятность: ВЫСОКАЯ**

При ошибке API или невалидном ключе метод `getNearbyRubricNames()` возвращает пустой `List.of()`, и скоринг молча ставит 50 баллов:

```java
// GisSearchService.java:68-71
} catch (Exception e) {
    log.warn("2GIS API недоступен ...");
    return List.of();  // ← пустой список
}

// PropertyScoringService.java:196-198
if (nearbyBusinesses.isEmpty()) {
    return MAX_COMPETITOR_SCORE; // ← 50 баллов, будто конкурентов нет
}
```

API-ключ `4864f04f-8983-435a-ae2e-06ed696ed550` мог истечь, быть заблокирован или исчерпать лимит запросов. При этом фронтенд «Что рядом» использует **Overpass API (OpenStreetMap)**, который работает без ключа и показывает кафе корректно.

**Как проверить:** посмотреть логи на наличие `"2GIS API недоступен"` или `"Ошибка парсинга ответа 2GIS"`.

---

### Гипотеза 2: 🟡 Несовпадение рубрик 2GIS с ключевыми словами — рубрики содержат составные названия

**Вероятность: СРЕДНЯЯ**

2GIS возвращает рубрики вроде `"Кафе"`, `"Кафе-бар"`, `"Чайхана"`, `"Кухня Узбекистана"`. Алгоритм матчинга ищет ключевое слово `"кафе"` в множестве слов рубрики.

Проблема с **дефисными** именами:
```java
// Regex удаляет дефис: replaceAll("[^а-яёa-z0-9\\s]", " ")
// "кафе-бар" → "кафе бар" → Set{"кафе", "бар"}
// Ключевое слово "кафе" → rubricWords.contains("кафе") → TRUE ✅
```

Это работает для `"кафе-бар"`, но **НЕ работает** для рубрик, которые 2GIS возвращает как абсолютно иные термины:
- `"Чайхана"` — нет в keywords `"кафе,бистро,столовая,кафетерий"` → **не матчится** ❌
- `"Быстрое питание"` — сматчится на `"Фастфуд"` (keyword `"быстрое питание"`), а не на `"Кафе"` → косвенный, не прямой
- `"Восточная кухня"` — не матчится ни с чем ❌

**Вывод:** список `twoGisKeywords` для категории `"Кафе"` **неполный** — нет таких терминов как `"чайхана"`, `"столовая"` (есть!), `"закусочная"`, `"кулинария"`, `"общественное питание"` и др.

---

### Гипотеза 3: 🟡 Ограничение пагинации — 2GIS возвращает нерелевантные заведения в первых 50 результатах

**Вероятность: СРЕДНЯЯ**

```java
// GisSearchService.java:27
private static final int PAGE_SIZE = 50;
```

Запрос `type=branch` без фильтра по рубрике возвращает **любые** заведения в радиусе: банки, аптеки, магазины одежды и т.д. В оживлённом районе Москвы в радиусе 1000м может быть **500+ заведений**, из которых API вернёт только первые 50.

Кафе «Северянин» и «Чайхана Дамаск» могут находиться **за пределами первой страницы** результатов 2GIS. Пагинация (`page` parameter) **не реализована** — запрашивается только первая страница.

**Проблема:** даже если рубрики настроены правильно, кафе могут просто не попасть в выборку из 50 заведений.

---

### Гипотеза 4: 🟡 Кэш возвращает устаревшие пустые данные после предыдущей ошибки API

**Вероятность: СРЕДНЕ-НИЗКАЯ**

```java
// CacheConfig.java:19-21
manager.setCaffeine(Caffeine.newBuilder()
        .expireAfterWrite(30, TimeUnit.MINUTES)
        .maximumSize(1000));
```

Spring `@Cacheable` кэширует **любой** результат, включая пустой `List.of()` после ошибки API. Если при первом запросе API был недоступен, последующие 30 минут все запросы с теми же округлёнными координатами будут получать пустой кэш → 50 баллов.

Кроме того, округление координат (`Math.round(lat * 1000)`) группирует точки в ячейки ~111×111 метров. Помещение на краю ячейки может получить кэшированный результат от другого помещения, у которого API вернул пустоту.

---

## Сводная таблица гипотез

| # | Гипотеза | Вероятность | Где проверять |
|---|----------|-------------|---------------|
| 1 | API-ключ 2GIS невалиден / лимит исчерпан → пустой ответ | 🔴 Высокая | Логи: `"2GIS API недоступен"` |
| 2 | Рубрики 2GIS не матчатся с `twoGisKeywords` (неполный словарь) | 🟡 Средняя | Логи: `"Рубрики первых N заведений"`, проверить вручную ответ 2GIS |
| 3 | PAGE_SIZE=50 без пагинации — кафе не попадают в выборку | 🟡 Средняя | Сделать тестовый запрос к 2GIS, проверить `total` vs `page_size` |
| 4 | Кэширование пустого ответа на 30 минут | 🟡 Средне-низкая | Рестарт приложения, повторный запрос |

---

## Рекомендации по исправлению

1. **Срочно:** проверить валидность API-ключа 2GIS вручную (curl-запрос)
2. **Не кэшировать пустые ответы** — добавить `condition` или `unless` в `@Cacheable`:
   ```java
   @Cacheable(value = "gisNearby", ..., unless = "#result.isEmpty()")
   ```
3. **Расширить `twoGisKeywords`** для категории «Кафе»: добавить `"чайхана"`, `"закусочная"`, `"кулинария"`, `"общепит"`, `"общественное питание"`, `"dining"`, `"столовая"` и пр.
4. **Реализовать пагинацию** в `GisSearchService` (параметр `page=1,2,3...` до исчерпания `total`)
5. **Добавить логирование** рубрик, которые НЕ сматчились, чтобы пополнять словарь:
   ```java
   if (matched == null) {
       log.debug("Рубрика не сматчилась ни с одной категорией: '{}'", rubric);
   }
   ```
