# Аудит «Проект поиска» и алгоритма скоринга помещений

> **Дата актуализации:** 2026-05-13
> **Статус:** ✅ Работающий end-to-end pipeline: проект поиска → скоринг 0–100 → объяснение AI
> **История:** документ объединяет ранее существовавшие `search_profile_scoring_audit.md` (создание проекта поиска) и `competitor_scoring_audit.md` (анализ конкурентов). Все ранее зафиксированные баги (конкурентный скор всегда 50, отсутствие пагинации, кэширование пустых ответов, провал плюрала «Аптеки» ↔ «аптека») закрыты — ниже описано текущее поведение системы.

---

## 1. Frontend-флоу: создание проекта поиска

Создание реализовано в `CreateSearchProfileScreen` на базе `Stepper` из трёх шагов.

### Шаги
1. **Основное**
   - `name` — название проекта.
   - `businessCategoryId` — ID целевой категории (`DropdownButton`, грузится из `/api/categories`).
2. **Финансы**
   - `minBudget`, `maxBudget` — диапазон бюджета, ₽/мес.
   - `minArea`, `maxArea` — диапазон площади, м².
3. **Технические критерии**
   - `minPowerKw` — мин. электрическая мощность.
   - `minCeilingHeight` — мин. высота потолков.
   - Булевы флаги: `requiresWater`, `requiresVentilation`, `requiresSeparateEntrance`, `requiresWc`, `requiresParking`, `requiresLoadingZone`.
4. (Опционально, не в Stepper-форме) **Геопредпочтения**
   - `centerLatitude`, `centerLongitude`, `searchRadiusMeters` — радиус поиска вокруг точки интереса.
   - `desiredNeighborCategoryIds` — множество желаемых соседей для синергического скоринга.

### Формирование запроса
В `_save()` собирается `Map<String, dynamic>` и автоконвертируется в JSON. Числа парсятся, булевы передаются как есть:

```dart
final data = <String, dynamic>{
  'name': _nameController.text.trim(),
  if (_selectedCategoryId != null) 'businessCategoryId': _selectedCategoryId,
  if (_minAreaController.text.isNotEmpty)    'minArea':    double.tryParse(_minAreaController.text),
  if (_maxAreaController.text.isNotEmpty)    'maxArea':    double.tryParse(_maxAreaController.text),
  if (_minBudgetController.text.isNotEmpty)  'minBudget':  double.tryParse(_minBudgetController.text),
  if (_maxBudgetController.text.isNotEmpty)  'maxBudget':  double.tryParse(_maxBudgetController.text),
  if (_minPowerController.text.isNotEmpty)   'minPowerKw': int.tryParse(_minPowerController.text),
  if (_minCeilingController.text.isNotEmpty) 'minCeilingHeight': double.tryParse(_minCeilingController.text),
  'requiresWater':            _requiresWater,
  'requiresVentilation':      _requiresVentilation,
  'requiresSeparateEntrance': _requiresSeparateEntrance,
  'requiresWc':               _requiresWc,
  'requiresParking':          _requiresParking,
  'requiresLoadingZone':      _requiresLoadingZone,
};
```

---

## 2. Приём на бэкенде

### Контроллер
`POST /api/search-profiles` (защищён `@PreAuthorize("hasRole('TENANT')")`). ID арендатора извлекается из JWT через `Principal`, далее — в сервис.

```java
@PostMapping
@PreAuthorize("hasRole('TENANT')")
public ResponseEntity<SearchProfile> createSearchProfile(
        @RequestBody CreateSearchProfileRequest request,
        Principal principal) {

    Long tenantId = extractUserId(principal);
    SearchProfile created = searchProfileService.createSearchProfile(tenantId, request);
    return ResponseEntity.status(HttpStatus.CREATED).body(created);
}
```

### DTO
`CreateSearchProfileRequest` (Lombok `@Data`) содержит все поля профиля. Jakarta-валидация (`@NotBlank`, `@NotNull`, `@Min`) **не настроена** — точка роста, чтобы блокировать пустые имена / отрицательные бюджеты на уровне DTO.

### Сервис
[SearchProfileService.java:34-41](backend/src/main/java/com/example/backend/service/SearchProfileService.java#L34-L41) — `createSearchProfile`:
- Грузит `User` по `tenantId`.
- `buildProfileFromRequest` мапит DTO → entity, разрешает `BusinessCategory` по ID, разрешает множество `desiredNeighbors` через `resolveCategories(ids)`.
- Сохраняет в `searchProfileRepository`.

Аналогичный `updateSearchProfile` (через `getProfileOwnedByTenant` — проверка владения). `getScoredPropertiesForProfile` берёт все `PUBLISHED` помещения и пропускает через `PropertyScoringService.scoreAndRankProperties(profile, list)`.

---

## 3. Алгоритм скоринга: 0–100 баллов = 4 компонента

[PropertyScoringService.java](backend/src/main/java/com/example/backend/service/PropertyScoringService.java) выдаёт итоговый балл как сумму четырёх независимых компонентов:

| Компонент   | Диапазон | Где смотреть в коде | Идея |
|-------------|----------|---------------------|------|
| Финансовый  | 0–30 | `calculateFinancialScore` | Площадь + бюджет в заданных интервалах |
| Технический | 0–20 | `calculateTechnicalScore` | Штрафная модель за несоответствие требований |
| Конкуренты  | 0–30 | `analyzeNeighborhood` → `competitorScore` | Реальные данные 2GIS о прямых/косвенных конкурентах |
| Синергия    | 0–20 | `analyzeNeighborhood` → `synergyScore` | Покрытие желаемых соседей |

> ⚠️ Важно: компонент конкурентов раньше был на шкале 0–50 и являлся источником бага «всегда 50». Сейчас шкала пересчитана и разделена с синергией (20 баллов отдельной полосы). Старые упоминания «MAX = 50» в прежних аудитах неактуальны.

### 3.1 Финансовый мэтч (0–30)

15 баллов за попадание площади в `[minArea, maxArea]`, 15 — за бюджет в `[minBudget, maxBudget]`. При выходе за границы не более чем на 20% начисляется частичный балл по `partialScore`. См. [PropertyScoringService.java:97-117](backend/src/main/java/com/example/backend/service/PropertyScoringService.java#L97-L117).

### 3.2 Технический мэтч (0–20)

Старт — `MAX_TECHNICAL_SCORE = 20`. За каждое нарушение — штраф:

| Несоответствие | −баллов |
|----------------|---------|
| Нужна вода, нет воды | 4 |
| Нужна вытяжка, нет вытяжки | 4 |
| Нужен отдельный вход, нет | 3 |
| `minPowerKw > 0`, фактической мощности не хватает | 3 |
| Нужен санузел, нет | 3 |
| Нужна парковка, нет | 2 |
| Нужна зона разгрузки, нет | 2 |
| Фактический потолок ниже `minCeilingHeight` | 2 |
| `RepairState == SHELL_AND_CORE` (безусловно) | 1 |

См. [PropertyScoringService.java:137-164](backend/src/main/java/com/example/backend/service/PropertyScoringService.java#L137-L164). Штрафы за «требования арендатора» срабатывают только если флаг в профиле = `TRUE`. Штраф за «черновую» — объективная характеристика, безусловная.

### 3.3 Конкуренты (0–30) и синергия (0–20)

Оба компонента считаются в одном проходе `analyzeNeighborhood` (один вызов 2GIS на помещение). См. [PropertyScoringService.java:188-323](backend/src/main/java/com/example/backend/service/PropertyScoringService.java#L188-L323).

**Конкуренты — шкала:**

| Прямые | Косвенные | Балл |
|--------|-----------|------|
| 0 | 0     | 30 |
| 0 | 1–2   | 24 |
| 0 | 3–5   | 18 |
| 0 | 6+    | 12 |
| 1 | —     | 12 |
| 2 | —     |  6 |
| 3–4 | —   |  3 |
| 5+ | —    |  0 |

- **Прямой**: рубрика заведения сматчилась в **ту же** `BusinessCategory`, что в `profile.businessCategory`.
- **Косвенный**: сматчилась в подкатегорию с **тем же родителем** (сосед по родителю в иерархии). Прямой исключает косвенный для одного и того же заведения (де-дупликация).

**Синергия:**

```
Если в профиле задано K желаемых категорий-соседей
  и среди nearby-бизнесов покрыты F из K  →  score = round(20 · F / K)
Если K = 0 (не указаны)                    →  score = 20 (без штрафа)
```

`directCompetitorNames`, `indirectCompetitorNames`, `synergyNeighborNames` собираются параллельно и отдаются во фронт через `ScoredPropertyDto` — фронт уже может рисовать списки имён рядом с прогресс-барами.

### 3.4 Лейблы / цвета

```
≥75 → 🔥 Отличный мэтч! / green
≥50 → 👍 Хороший вариант / yellow
≥25 → ⚠️ Частичное совпадение / red
<25 → ❌ Не подходит       / red
```

---

## 4. Интеграция с 2GIS Places API

### 4.1 Запрос
[GisSearchService.java](backend/src/main/java/com/example/backend/service/GisSearchService.java) — клиент `https://catalog.api.2gis.com/3.0/items`. Параметры:

| Параметр | Значение | Комментарий |
|----------|----------|-------------|
| `point`     | `{lon},{lat}` | Порядок для 2GIS — long,lat |
| `radius`    | `min(searchRadiusMeters, 5000)`, default `1000` | м |
| `type`      | `branch` | Только филиалы / заведения |
| `fields`    | `items.rubrics,items.name_ex` | Имя + рубрики |
| `key`       | из `application.properties` (`twogis.api.key`) | — |
| `page_size` | **10** (`PAGE_SIZE`) | Лимит 2GIS API: 1..10 |
| `page`      | `1..N` пока `page ≤ totalPages && page ≤ MAX_PAGES (20)` | До 200 заведений |

> Пагинация реализована: цикл по страницам с порогом `MAX_PAGES = 20` — суммарно до **200 заведений** в выборке. Ранее API дергался только за первой страницей (50 шт.) и оживлённые районы Москвы в радиусе 1 км теряли релевантные заведения; этот баг закрыт.

### 4.2 Парсинг ответа
`parseBusinesses` строит `List<NearbyBusiness(name, rubrics)>`:
- Имя берётся из `name_ex.primary`, fallback — `name`, fallback — первая рубрика.
- Рубрики — `items[].rubrics[].name` → `toLowerCase()`.
- Если у объекта нет рубрик — пропускается.

### 4.3 Кэширование
```java
@Cacheable(
    value = "gisNearby",
    key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + #radiusMeters",
    unless = "#result == null || #result.isEmpty()"
)
```
- Каффеин-кэш: `expireAfterWrite(30 min)`, `maximumSize=1000` (см. [CacheConfig.java](backend/src/main/java/com/example/backend/config/CacheConfig.java)).
- Округление координат — 3-й знак (~111 м) → группирует точки в ~111×111 м ячейки.
- `unless` гарантирует: пустой ответ при ошибке API **не** кэшируется → повторный запрос сходит в сеть. Это закрывает прежний баг «30 минут пустоты после первой ошибки».

### 4.4 Поведение при сбое
- HTTP-ошибка → `log.warn("2GIS API недоступен…")` → `return null` для страницы → внешний цикл прерывается → `nearbyBusinesses` пустой.
- Невалидный JSON → `log.warn("Ошибка парсинга страницы…")` → прерывание.
- В обоих случаях `analyzeNeighborhood` уходит в ранний выход: `competitorScore = 30`, `synergyScore = 20` (если у профиля нет desired) или `0` (если есть). Это компромисс: при недоступности 2GIS мы не штрафуем помещение, но и не выдаём «синергию по умолчанию», если арендатор её явно ожидал.

---

## 5. Каталог рубрик 2GIS и `twoGisKeywords` категорий

### 5.1 Источник правды
[BusinessCategory.twoGisKeywords](backend/src/main/java/com/example/backend/entity/BusinessCategory.java) — CSV-строка с ключевыми словами категории. Заполняется в [DataInitializer](backend/src/main/java/com/example/backend/config/DataInitializer.java) при старте приложения:

1. Идём по дереву категорий, для каждой — seed-список ключей (написан вручную).
2. Имя категории в lowercase добавляется в seed-набор.
3. `GisRubricCatalogService.expandKeywords(seeds)` подтягивает официальный каталог рубрик 2GIS (`/2.0/catalog/rubric/list` для `region_id=1` Москва) и возвращает все канонические имена рубрик, которые **морфологически соответствуют** хоть одному seed-слову.
4. Итог — объединение `canonical_2gis_names ∪ seeds` сохраняется в `twoGisKeywords`. Так покрываются и случаи, когда 2GIS-рубрика звучит иначе (canonical имя), и случаи, когда конкретной рубрики в 2GIS нет (seed остаётся).

Каталог рубрик грузится **lazy + один раз** в памяти (`cachedRubrics`), при сбое 2GIS падаем на чистый seed без расширения.

### 5.2 Текущее дерево категорий

| Корень | Подкатегории |
|--------|---------------|
| Еда и напитки | Продуктовый магазин, Кофейня, Ресторан, Кафе, Пекарня, Кондитерская, Фастфуд, Бар |
| Красота и здоровье | Аптека, Парикмахерская, Салон красоты, Маникюр и педикюр, Косметология, Медицинский центр, Оптика |
| Товары | Одежда, Обувь, Ювелирный магазин, Цветочный магазин, Зоомагазин, Спорттовары, Детские товары |
| Сервис и услуги | ПВЗ, Банк, Химчистка, Ремонт электроники, Туристическое агентство |
| Образование и развитие | Детский центр, Учебный центр, Фитнес-клуб |

Корни (`Еда и напитки`, `Красота и здоровье` и т.д.) сами не имеют `twoGisKeywords` — используются только как контейнеры для расчёта «косвенных» (общий родитель).

---

## 6. Матчинг рубрик 2GIS ↔ категорий — русская морфология

### 6.1 Проблема, которую решал последний фикс
2GIS отдаёт канонические имена рубрик во **множественном числе**: `Аптеки`, `Кофейни`, `Парикмахерские`, `Цветочные магазины`. Seed-keywords в БД — в единственном (`аптека`, `кофейня`, `парикмахерская`). Прежний матчер использовал `Set<String>.contains(kw)` для односложных и `String.contains(kw)` для многословных — оба провальны на плюрале (`{"аптеки"}.contains("аптека")` → false; `"аптеки".contains("аптека")` → false). В результате при выборе категории «Аптека» соседние аптеки молча игнорировались, и единственным конкурентом оказывались косвенные «салоны красоты», у которых seed-keywords содержат словарные основы без характерных русских окончаний (`маникюр`, `массаж`, `косметология`).

### 6.2 Решение: лёгкий русский стеммер
[RussianRubricMatcher.java](backend/src/main/java/com/example/backend/service/RussianRubricMatcher.java) — utility-класс, реализующий морфологическое сравнение.

**Алгоритм стемминга:**
- Lowercase + `ё → е` + удаление не-буквенно-цифровых символов (заменяются пробелом).
- Токенизация по `\s+`.
- Для каждого токена пытаемся срезать **самое длинное** подходящее окончание инфлекции, при условии что основа ≥ 3 символов:

```
4 символа: иями
3 символа: ыми ими ями ами  ого его ому ему  иям иях иев
2 символа: ой ый ий ая яя   ое ее ые ие     ии ия ью ье ья
           ом ем ою ею ей    ев ов ах ям ам ую юю ых их ым им
1 символ:  а я о е у ю ы и
```

**Алгоритм матчинга:**
- Из рубрики получаем множество основ (`stemSet`).
- Для каждого keyword тоже считаем множество основ.
- Многословный keyword матчится, если **все** его основы содержатся в основах рубрики (`rubricStems.containsAll(kwStems)`).
- Минимальная длина основы 3 — защищает короткое `бар`: оно остаётся `бар`, а `барбершопы` стеммится в `барбершоп`, пересечения нет → ложный матч предотвращён.
- Деривация (например «коктейльный» ↔ «коктейль») **намеренно не обрабатывается** — это словообразование, не словоизменение, и эвристики легко дают переобобщения. Если нужно — заведите оба корня в seed.

### 6.3 Что это чинит на конкретных примерах

| Seed | 2GIS рубрика | До фикса | Сейчас |
|------|--------------|----------|--------|
| `аптека` | Аптеки | ❌ | ✅ (стем `аптек ⊆ аптек`) |
| `оптика` | Оптики | ❌ | ✅ |
| `кофейня` | Кофейни | ❌ | ✅ |
| `парикмахерская` | Парикмахерские | ❌ | ✅ |
| `ресторан` | Рестораны | ❌ | ✅ |
| `ювелирный магазин` | Ювелирные магазины | ❌ | ✅ (`ювелирн`, `магазин` ⊆ рубрики) |
| `цветочный магазин` | Цветочные магазины | ❌ | ✅ |
| `кафе` | Кафе | ✅ | ✅ (foreign-word, основа стабильна) |
| `бар` | Барбершопы | ⚠️ безопасно (не матчилось) | ✅ безопасно (не матчится) |
| `бар` | Бары | ❌ | ✅ |
| `цветочный магазин` | Магазины (generic) | ❌ ложноположительно | ✅ корректно НЕ матчится |

### 6.4 Применение в двух местах
- **Скоринг** ([PropertyScoringService.matchRubricToCategory](backend/src/main/java/com/example/backend/service/PropertyScoringService.java#L325-L352)) — на каждое заведение, на каждую его рубрику, на каждую категорию из БД. Стемы рубрики считаются один раз на рубрику.
- **Старт приложения** ([GisRubricCatalogService.expandKeywords](backend/src/main/java/com/example/backend/service/GisRubricCatalogService.java#L49-L87)) — расширяет seed-keywords каноническими именами 2GIS-рубрик. Каталог 2GIS (~2-3к записей) пред-стеммится один раз, дальше `containsAll` по множествам.

### 6.5 Логирование непокрытых рубрик
В `analyzeNeighborhood` логируется (`log.warn("[COMP-NO-MATCH] …")`) ситуация, когда **ни одна** из найденных 2GIS-рубрик не сматчилась ни с одной категорией — с примером первых пяти `(name, rubrics)`. Это позволяет быстро ловить новые рубрики 2GIS (например региональные термины) и пополнять seed.

---

## 7. Закрытые баги (исторический контекст)

| # | Баг | Как закрыт |
|---|-----|------------|
| 1 | `competitor score == 50` всегда — 2GIS-ответ пустой → ранний выход | Логи `[COMP-NO-MATCH]` + `unless = #result.isEmpty()` + пагинация |
| 2 | `PAGE_SIZE=50` без пагинации, кафе/аптеки терялись в оживлённых районах | Реализована пагинация до 200 заведений (`MAX_PAGES=20 × PAGE_SIZE=10`) |
| 3 | Кэш сохранял пустой `List.of()` после ошибки API на 30 минут | `unless = "#result == null || #result.isEmpty()"` в `@Cacheable` |
| 4 | Конкуренты не находились из-за русского плюрала (`Аптеки` ↔ `аптека`) | `RussianRubricMatcher` — стемминг инфлекции, единый путь и в скоринге, и в расширении keywords |
| 5 | Шкала 0–50 для конкурентов конфликтовала с финансовым+техническим (итог >100) | Шкала пересмотрена: конкуренты 0–30, синергия 0–20, всё суммирует в 100 |

---

## 8. Открытые точки роста

1. **Jakarta-валидация на DTO** — добавить `@NotBlank name`, `@NotNull businessCategoryId`, `@Positive` для бюджетов/площадей; повесить `@Valid` на параметр контроллера.
2. **Тонкая настройка деривации** — `коктейльный бар` ↔ `Коктейль-бары` сейчас зависит от ручного seed. Если такие пары будут встречаться часто, имеет смысл прикрутить Lucene `RussianLightStemFilter` целиком и заменить наш стеммер.
3. **Фронтовое отображение `directCompetitorNames` / `indirectCompetitorNames` / `synergyNeighborNames`** — DTO уже их отдаёт, но карточка скоринга на `PropertyDetailsScreen` рисует только 4 прогресс-бара. Полезно показать сами имена «Аптека №1 в 250 м», «BeautyStudio в 400 м».
4. **Блок «Что рядом»** на карточке арендатора всё ещё ходит в Overpass API и ищет только `subway`/`cafe`/`university`. Не связан со скорингом и не учитывает категорию проекта. Кандидат на унификацию: брать данные из той же 2GIS-выборки, что и скоринг — тогда визуал в карточке гарантированно совпадёт с тем, на чём посчитан балл.
5. **Регион 2GIS** прописан как константа `twogis.region.id=1` (Москва). Для масштабирования за пределы Москвы — параметризовать по геоточке помещения (lookup региона по lat/lon в `2GIS` `/region/search`).
