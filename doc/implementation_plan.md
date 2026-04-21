# 🏙️ Street Retail Aggregator — PRD Implementation Plan

Реализация функционала из PRD: умный скоринг помещений, встроенный чат, аналитика, инфраструктура окружения и push-уведомления.

---

## User Review Required

> [!IMPORTANT]
> **Масштаб проекта.** PRD содержит ~5 крупных фич. Предлагаю двигаться **итеративно по фазам** (от бэкенда к фронтенду), чтобы каждая фаза была рабочей и тестируемой. Подтверди, что согласен с порядком.

> [!WARNING]
> **Чувствительные данные.** В `application.properties` находятся реальные пароли от Gmail и БД. При коммите в публичный репозиторий стоит вынести их в `.env` или Spring Profiles. Хочешь, чтобы я это сделал в рамках этого плана?

> [!CAUTION]
> **WebSocket чат (Фаза 3)** — самая сложная фича. Потребуется добавить зависимость `spring-boot-starter-websocket` и `stomp_dart_client` во Flutter. Это значительно увеличит объём работы. Если хочешь — можно начать с упрощённого чата через polling (REST), а WebSocket добавить позже.

## Open Questions

1. **Overpass API vs Yandex Geosearch?** PRD упоминает оба. Overpass API (OpenStreetMap) — бесплатный, но менее точный для РФ. Yandex Geosearch — платный, но данные по Москве полнее. Какой предпочитаешь?
2. **Firebase vs свой WebSocket?** Для чата и push-уведомлений Firebase — быстрее в интеграции. Чистый Spring WebSocket — без внешних зависимостей. Что ближе?
3. **Какие фазы делать первыми?** Рекомендую начать с Фазы 1 (Скоринг) — это ядро продукта. Можно остановиться после любой фазы.

---

## 📊 Текущее состояние проекта (Аудит)

### Что уже реализовано:

| Компонент | Статус | Детали |
|-----------|--------|--------|
| Auth (JWT) | ✅ Готово | Регистрация, логин, верификация email, роли TENANT/LANDLORD/ADMIN |
| Property CRUD | ✅ Готово | Создание, редактирование, архивация (soft delete), расширенная карточка |
| BusinessCategory | ✅ Готово | Иерархическое дерево категорий (parent/child) |
| Favorites | ✅ Готово | ManyToMany через таблицу `favorites` |
| Applications | ✅ Готово | Заявки с cover letter, статусы PENDING→ACCEPTED/REJECTED, причина отказа |
| Рекомендации v1 | ⚠️ Примитивно | `calculateRecommendationScore()` — только проверка конкурентов и hasWater. Хардкод `categoryId == 3L` |
| Flutter UI | ✅ Готово | Карта (Yandex MapKit), детали помещения (Sliver), избранное, заявки, профиль |
| TenantProfile | ⚠️ Минимальный | Только name/inn/phone + одна targetBusinessCategory |

### Что отсутствует:
- ❌ `SearchProfile` (проект поиска арендатора)
- ❌ Полноценный скоринг (финансы, техника, локация, конкуренты)
- ❌ Чат между Landlord и Tenant
- ❌ Аналитика для Landlord
- ❌ Инфраструктура окружения (POI)
- ❌ Push-уведомления

---

## Фаза 1: SearchProfile + PropertyScoringService (Бэкенд)

> Ядро продукта — «Tinder для бизнеса». Арендатор создаёт проект поиска, алгоритм оценивает каждое помещение по 4 критериям.

---

### Backend — Новые сущности

#### [NEW] [SearchProfile.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/entity/SearchProfile.java)

Новая JPA-сущность — «Проект поиска арендатора». Один арендатор может иметь несколько проектов (например, «Открыть кофейню» и «Открыть ПВЗ»).

```java
@Entity
@Table(name = "search_profiles")
public class SearchProfile {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    private User tenant;

    private String name;                          // "Открыть кофейню на Арбате"

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "business_category_id")
    private BusinessCategory businessCategory;    // Категория бизнеса

    // --- Финансовые критерии ---
    private BigDecimal minArea;
    private BigDecimal maxArea;
    private BigDecimal minBudget;
    private BigDecimal maxBudget;

    // --- Технические критерии ---
    private Integer minPowerKw;
    private Boolean requiresWater;
    private Boolean requiresVentilation;
    private Boolean requiresSeparateEntrance;

    // --- Локация ---
    private BigDecimal centerLatitude;            // Центр поиска
    private BigDecimal centerLongitude;
    private Integer searchRadiusMeters;           // Радиус в метрах

    // --- Синергия (желаемые соседи) ---
    @ManyToMany
    @JoinTable(name = "search_profile_desired_neighbors", ...)
    private Set<BusinessCategory> desiredNeighbors;

    private Boolean isActive;                     // Активный проект
    @CreationTimestamp
    private LocalDateTime createdAt;
}
```

**Изменения в БД** (через `ddl-auto=update`):
- Таблица `search_profiles`
- Join-таблица `search_profile_desired_neighbors`

---

#### [NEW] [SearchProfileRepository.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/repository/SearchProfileRepository.java)

```java
public interface SearchProfileRepository extends JpaRepository<SearchProfile, Long> {
    List<SearchProfile> findByTenantId(Long tenantId);
    List<SearchProfile> findByTenantIdAndIsActiveTrue(Long tenantId);
}
```

---

#### [NEW] [CreateSearchProfileRequest.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/dto/CreateSearchProfileRequest.java)

DTO для создания/обновления проекта поиска.

---

#### [NEW] [ScoredPropertyDto.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/dto/ScoredPropertyDto.java)

DTO ответа со скорингом:
```java
public class ScoredPropertyDto {
    private Property property;
    private int totalScore;           // 0-100
    private int financialScore;       // 0-20
    private int technicalScore;       // 0-40
    private int locationScore;        // 0-25
    private int competitorScore;      // 0-15
    private String matchLabel;        // "Отличный мэтч!", "Хороший вариант", "Не подходит"
}
```

---

### Backend — Сервис скоринга

#### [NEW] [PropertyScoringService.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/service/PropertyScoringService.java)

Основной алгоритм. Принимает `SearchProfile` и список `Property`, возвращает `List<ScoredPropertyDto>`.

**Алгоритм:**

```
┌──────────────────────────────────────────────────┐
│            PropertyScoringService                │
├──────────────────────────────────────────────────┤
│  scoreProperties(SearchProfile, List<Property>)  │
│                                                  │
│  1. calculateFinancialScore(property, profile)   │
│     - Площадь в диапазоне [minArea, maxArea]?    │
│     - Цена в диапазоне [minBudget, maxBudget]?   │
│     → 0..20 баллов                               │
│                                                  │
│  2. calculateTechnicalScore(property, profile)   │
│     - Есть вода, если нужна вода?                │
│     - Есть вытяжка, если нужна вытяжка?          │
│     - Достаточно кВт?                            │
│     - Есть отдельный вход?                       │
│     → 0..40 баллов (критические требования)      │
│                                                  │
│  3. calculateLocationScore(property, profile)    │
│     - Расстояние от центра поиска (Haversine)    │
│     - Наличие desiredNeighbors в existingNeighbors│
│     → 0..25 баллов                               │
│                                                  │
│  4. calculateCompetitorScore(property, profile)  │
│     - Есть ли конкуренты (та же категория)       │
│       в existingNeighbors помещения?             │
│     → 0..15 баллов (15 если нет конкурентов)     │
│                                                  │
│  ИТОГО: sum → 0..100                             │
└──────────────────────────────────────────────────┘
```

---

#### [NEW] [SearchProfileService.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/service/SearchProfileService.java)

CRUD для проектов поиска + вызов скоринга.

---

#### [NEW] [SearchProfileController.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/controller/SearchProfileController.java)

REST API:
| Метод | Путь | Описание |
|-------|------|----------|
| `POST` | `/api/search-profiles` | Создать проект поиска |
| `GET` | `/api/search-profiles` | Мои проекты поиска |
| `GET` | `/api/search-profiles/{id}` | Получить по ID |
| `PUT` | `/api/search-profiles/{id}` | Обновить проект |
| `DELETE` | `/api/search-profiles/{id}` | Удалить проект |
| `GET` | `/api/search-profiles/{id}/scored-properties` | **⭐ Ключевой эндпоинт: получить помещения со скорингом** |

#### [MODIFY] [PropertyService.java](file:///c:/Games/street-retail-aggregator/backend/src/main/java/com/example/backend/service/PropertyService.java)

- Удалить старый `calculateRecommendationScore()` (хардкод с `categoryId == 3L`)
- `getRecommendedPropertiesForTenant()` будет делегировать в `PropertyScoringService`

---

## Фаза 2: Интеграция скоринга в Flutter UI

---

### Frontend — Новые модели

#### [NEW] `frontend/lib/src/domain/search_profile.dart`

Dart-модель `SearchProfile` с `fromJson()`.

#### [NEW] `frontend/lib/src/domain/scored_property.dart`

Dart-модель `ScoredProperty` — обёртка над `Property` с полями `totalScore`, `financialScore`, `technicalScore`, `locationScore`, `competitorScore`, `matchLabel`.

---

### Frontend — Сервис

#### [NEW] `frontend/lib/src/services/search_profile_service.dart`

API-клиент для CRUD проектов поиска и получения скоринга.

---

### Frontend — UI

#### [NEW] `frontend/lib/src/presentation/screens/tenant/search_profiles_screen.dart`

Экран «Мои проекты поиска» — список карточек с названием и категорией. Кнопка «+ Новый проект».

#### [NEW] `frontend/lib/src/presentation/screens/tenant/create_search_profile_screen.dart`

Форма создания проекта (Stepper / Wizard):
- Шаг 1: Название + Категория бизнеса
- Шаг 2: Бюджет и площадь (RangeSlider)
- Шаг 3: Технические требования (чекбоксы)
- Шаг 4: Локация (карта с радиусом)

#### [MODIFY] `frontend/lib/src/presentation/screens/tenant/map_screen.dart`

- Добавить выпадающий список (Dropdown) для переключения активного проекта поиска
- При выборе проекта → вызывать `/api/search-profiles/{id}/scored-properties`
- Отображать скоринг на маркерах (цвет: зелёный >75, жёлтый 50-75, красный <50)

#### [MODIFY] `frontend/lib/src/presentation/screens/tenant/property_details_screen.dart`

- Добавить бейджик «Подходит на XX%» поверх фото в SliverAppBar
- Показывать breakdown скоринга (4 полоски прогресса под заголовком)

#### [MODIFY] `frontend/lib/src/presentation/screens/tenant/tenant_main_screen.dart`

- Добавить 5-ю вкладку «Проекты» (icon: `Icons.search`) или интегрировать через FAB на экране карты

---

## Фаза 3: Встроенный чат (Real-time)

> [!IMPORTANT]
> Это самая сложная фаза. Требуется WebSocket (STOMP) на бэкенде и `stomp_dart_client` на фронтенде. Альтернатива — REST polling каждые 5 секунд (проще, но менее real-time).

---

### Backend

#### [NEW] Зависимость: `spring-boot-starter-websocket` в `build.gradle`

#### [NEW] `ChatMessage.java` — JPA-сущность сообщения
```
id, senderId, receiverId, applicationId, content, timestamp, isRead
```

#### [NEW] `ChatRoom.java` — JPA-сущность комнаты чата
```
id, applicationId (привязка к заявке), landlordId, tenantId
```

#### [NEW] `WebSocketConfig.java` — конфигурация STOMP
#### [NEW] `ChatController.java` — REST + WebSocket эндпоинты
#### [NEW] `ChatService.java` — бизнес-логика чата

### Frontend

#### [NEW] `chat_service.dart` — подключение к STOMP / REST polling
#### [NEW] `chat_screen.dart` — экран чата (пузырьки сообщений, ввод)
#### [MODIFY] `my_applications_screen.dart` — кнопка «Чат» рядом с каждой заявкой

---

## Фаза 4: Аналитика, инфраструктура окружения, Push-уведомления

---

### 4A: Аналитика для Арендодателя

#### Backend
- [NEW] `PropertyViewEvent.java` — сущность (propertyId, viewedBy, timestamp)
- [NEW] `AnalyticsService.java` — подсчёт просмотров, добавлений в избранное
- [NEW] `AnalyticsController.java` — `GET /api/analytics/my-properties`

#### Frontend
- [NEW] `analytics_screen.dart` — графики (просмотры, избранное, заявки) с помощью `fl_chart`

---

### 4B: Инфраструктура окружения (POI)

#### Backend
- [NEW] `InfrastructureService.java` — клиент к Overpass API (или Yandex Geosearch)
- Запрос: «Найди все кафе, метро, ВУЗы в радиусе 500м от координат»
- [NEW] `InfrastructureController.java` — `GET /api/infrastructure?lat=X&lon=Y&radius=500`

#### Frontend
- [MODIFY] `property_details_screen.dart` — новая секция «Инфраструктура рядом» с иконками и расстоянием

---

### 4C: Push-уведомления (Firebase Cloud Messaging)

#### Backend
- [NEW] Зависимость: `firebase-admin` SDK
- [NEW] `NotificationService.java` — отправка push через FCM
- [MODIFY] `ApplicationService.java` — вызывать NotificationService при создании/обновлении заявки

#### Frontend
- [NEW] Зависимость: `firebase_messaging` + `firebase_core` в `pubspec.yaml`
- [NEW] `notification_service.dart` — инициализация FCM, обработка foreground/background
- [MODIFY] `main.dart` — инициализация Firebase

---

## Verification Plan

### Automated Tests

```bash
# Бэкенд — компиляция и запуск
cd backend && ./gradlew bootRun

# Тест скоринга через curl
curl -X POST http://localhost:8080/api/search-profiles \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Тест кофейня","businessCategoryId":3,"minArea":30,"maxArea":100,"minBudget":50000,"maxBudget":200000}'

curl http://localhost:8080/api/search-profiles/1/scored-properties \
  -H "Authorization: Bearer <token>"

# Фронтенд — сборка
cd frontend && flutter build apk --debug
```

### Manual Verification

- Создать SearchProfile через Flutter UI
- Проверить, что скоринг корректно ранжирует помещения
- Проверить бейджик «Подходит на XX%» на карте и в деталях
- Отправить сообщение в чате и получить его в реальном времени
- Проверить аналитику после нескольких просмотров

---

## Рекомендуемый порядок реализации

```mermaid
graph LR
    A["Фаза 1\nSearchProfile +\nScoring Backend"] --> B["Фаза 2\nScoring UI\nFlutter"]
    B --> C["Фаза 3\nЧат\nWebSocket"]
    C --> D["Фаза 4\nАналитика +\nPOI + Push"]

    style A fill:#22c55e,color:#fff
    style B fill:#3b82f6,color:#fff
    style C fill:#f59e0b,color:#fff
    style D fill:#8b5cf6,color:#fff
```

> [!TIP]
> **Рекомендация:** Начнём с **Фазы 1** (SearchProfile + PropertyScoringService). Это занимает ~5-7 файлов на бэкенде и даёт рабочий API, который можно сразу проверить через Postman/curl. После подтверждения — переходим к Фазе 2 (Flutter UI).
