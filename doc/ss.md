Сводка проекта: Street Retail Aggregator
1. Общая суть проекта
Что разрабатываем: Агрегатор коммерческой недвижимости (стрит-ритейл). Арендодатели размещают помещения, арендаторы ищут их и получают персонализированный AI-скоринг под свой бизнес-проект.

Главная уникальная функция: При открытии карточки помещения система делает реальный запрос в 2GIS Places API, находит все организации в заданном радиусе и оценивает конкурентную среду. Арендатор видит числовой скор (0–100) с расшифровкой почему помещение подходит или не подходит под его бизнес.

Стек:

Backend: Java 21, Spring Boot 4.0.3, Spring Security (JWT), Spring Cache + Caffeine, Spring Data JPA (Hibernate), PostgreSQL
Frontend: Flutter (Dart), Dio (HTTP), flutter_secure_storage, yandex_mapkit (карта), fl_chart (графики)
Инфраструктура: Docker (PostgreSQL-контейнер retail-postgres), порт 5434 наружу → 5432 внутри
2. Архитектура и структура

street-retail-aggregator/
├── backend/
│   └── src/main/java/com/example/backend/
│       ├── config/
│       │   ├── CacheConfig.java          — Caffeine кэш (gisNearby + propertyScore, TTL 30 мин, max 1000)
│       │   ├── DataInitializer.java      — Seed иерархии категорий при старте (идемпотентный)
│       │   └── SecurityConfig.java       — JWT фильтр, роли LANDLORD/TENANT
│       ├── controller/
│       │   ├── PropertyController.java   — CRUD помещений + /score + /favorites
│       │   ├── SearchProfileController.java — CRUD проектов поиска + /scored-properties
│       │   ├── CategoryController.java   — /categories (дерево) + /categories/flat
│       │   └── AnalyticsController.java  — просмотры и статистика арендодателя
│       ├── dto/
│       │   ├── ScoredPropertyDto.java    — {property, totalScore, financialScore, technicalScore, competitorScore, matchLabel, matchColor}
│       │   ├── CreatePropertyRequest.java
│       │   ├── CreateSearchProfileRequest.java
│       │   └── BusinessCategoryDto.java
│       ├── entity/
│       │   ├── Property.java             — помещение со всеми полями
│       │   ├── SearchProfile.java        — проект поиска арендатора
│       │   ├── BusinessCategory.java     — иерархические категории (@JsonIgnore на subCategories!)
│       │   ├── User.java                 — implements UserDetails, роли через Enum
│       │   └── TenantProfile/LandlordProfile.java
│       ├── service/
│       │   ├── PropertyScoringService.java ← ГЛАВНЫЙ, работали последним
│       │   ├── GisSearchService.java       — 2GIS Places API клиент с @Cacheable
│       │   ├── PropertyService.java
│       │   ├── SearchProfileService.java
│       │   └── InfrastructureService.java  — Overpass API (метро/кафе/универы рядом)
│       └── repository/
│           └── BusinessCategoryRepository.java — добавлен findByName()
│
├── frontend/lib/src/
│   ├── domain/
│   │   ├── property.dart
│   │   └── search_profile.dart           — SearchProfile + ScoredProperty (fromJson)
│   ├── services/
│   │   ├── property_service.dart         — getAllProperties, scoreProperty(id) → GET /properties/{id}/score
│   │   ├── search_profile_service.dart   — CRUD профилей + getScoredProperties()
│   │   ├── analytics_service.dart        — logPropertyView, getMyAnalytics (AnalyticsDto?)
│   │   ├── infrastructure_service.dart   — getInfrastructureNearby → GET /api/infrastructure
│   │   └── category_service.dart         — getAllCategories() /categories/flat
│   └── presentation/screens/
│       ├── tenant/
│       │   ├── property_details_screen.dart ← последние правки UI
│       │   ├── map_screen.dart
│       │   ├── search_profiles_screen.dart  — CreateSearchProfileScreen (Stepper, 3 шага)
│       │   └── tenant_main_screen.dart
│       └── landlord/
│           ├── analytics_screen.dart        — FutureBuilder<AnalyticsDto?>
│           └── my_properties_screen.dart
│
└── backend/src/main/resources/
    └── application.properties
        twogis.api.key=4864f04f-8983-435a-ae2e-06ed696ed550
        spring.datasource.url=jdbc:postgresql://localhost:5434/retail_aggregator
        spring.datasource.username=myuser
        spring.datasource.password=mypassword
        spring.jpa.hibernate.ddl-auto=update   ← Hibernate сам добавляет столбцы
3. Текущее состояние — что работает
Backend
JWT-авторизация — регистрация/логин, роли LANDLORD / TENANT
CRUD помещений — создание, редактирование, мягкое удаление (статус ARCHIVED), фильтр PUBLISHED в ленте
Избранное — добавить/удалить/список
Проекты поиска — CRUD с 3-шаговой формой в Flutter
Скоринг — полностью работающий, через 2GIS, описан ниже
Категории — иерархия 5 родителей × ~30 дочерних, в БД чистые
Аналитика — логирование просмотров, агрегация для арендодателя
Инфраструктура — Overpass API (метро/кафе/универы рядом от помещения)
Frontend
Карта (Yandex MapKit) с маркерами помещений
Карточка помещения с блоком скоринга (3 полоски прогресса) и расширенными техническими тегами
Рекомендательный список со скорингом
Экран "Проекты поиска" (Stepper 3 шага) с расширенными техническими требованиями
Экран аналитики с графиком (fl_chart)
4. Ключевой код — актуальные версии
ScoredPropertyDto.java (backend/dto)

@Data @Builder @NoArgsConstructor @AllArgsConstructor
public class ScoredPropertyDto {
    private Property property;
    private int totalScore;       // 0-100
    private int financialScore;   // 0-30
    private int technicalScore;   // 0-20
    private int competitorScore;  // 0-50
    private String matchLabel;    // "🔥 Отличный мэтч!", "👍 Хороший вариант", ...
    private String matchColor;    // "green", "yellow", "red"
    // locationScore УДАЛЁН
}
Property.java — технические поля (АКТУАЛЬНЫЙ СПИСОК)

// Существующие (используются в скоринге):
private Integer powerKw;
private Boolean hasWater;
private Boolean hasVentilation;
private Boolean hasSeparateEntrance;
private BigDecimal ceilingHeight;   // в метрах
private RepairState repairState;    // SHELL_AND_CORE / PRE_FINISHING / TYPICAL / DESIGNER

// Новые (добавлены в текущей сессии):
private Boolean hasWc;          // санузел в помещении
private Boolean hasParking;     // парковка рядом
private Boolean hasLoadingZone; // зона разгрузки/погрузки

// Существуют, но не влияют на скоринг:
private String parking;         // старое строковое поле, не удалять (в БД есть данные)
private LayoutType layout;
private HeatingType heatingType;
private FurnitureState furnitureState;
SearchProfile.java — технические требования (АКТУАЛЬНЫЙ СПИСОК)

// Существующие:
private Integer minPowerKw;
private Boolean requiresWater;
private Boolean requiresVentilation;
private Boolean requiresSeparateEntrance;

// Новые (добавлены в текущей сессии):
private Boolean requiresWc;
private Boolean requiresParking;
private Boolean requiresLoadingZone;
private BigDecimal minCeilingHeight;   // мин. высота потолков, м
PropertyScoringService.java — ФИНАЛЬНАЯ ВЕРСИЯ

// Веса: Финансы=30, Технические=20, Конкуренты=50.

// Технический скоринг — штрафная модель (старт 20, вычитаем):
// Нет воды (обяз.)           -4
// Нет вытяжки (обяз.)        -4
// Нет отд. входа (обяз.)     -3
// Мощность мала (обяз.)      -3
// Нет санузла (обяз.)        -3
// Нет парковки (обяз.)       -2
// Нет зоны разгрузки (обяз.) -2
// Потолок ниже мин. (обяз.)  -2
// SHELL_AND_CORE (всегда)    -1   ← безусловный, не зависит от требований
// Итого потенц. штраф: -24, пол = 0, max остаётся 20.

public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
    List<BusinessCategory> allCategories = businessCategoryRepository.findAll(); // один раз
    return properties.stream()
            .map(p -> scoreInternal(profile, p, allCategories))
            .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
            .collect(Collectors.toList());
}

// Конкурентная шкала (0-50):
// 0 прямых, 0 косвенных → 50
// 0 прямых, 1-2 косвенных → 40
// 0 прямых, 3-5 косвенных → 30
// 0 прямых, 6+ косвенных → 20
// 1 прямой → 20
// 2 прямых → 10
// 3-4 прямых → 5
// 5+ прямых → 0
GisSearchService.java — 2GIS клиент

@Cacheable(
    value = "gisNearby",
    key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + #radiusMeters"
)
public List<String> getNearbyRubricNames(double lat, double lon, int radiusMeters) {
    // URL: https://catalog.api.2gis.com/3.0/items?point=LON,LAT&radius=R&type=branch&fields=items.rubrics
    // ВАЖНО: 2GIS принимает lon,lat (не lat,lon)
    // Возвращает дедуплицированные строчные названия рубрик
    // При ошибке — пустой список (не кидает исключение)
}
BusinessCategory.java — КРИТИЧЕСКИ ВАЖНАЯ ПРАВКА

@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "parent_id")
@JsonIgnoreProperties({"parentCategory", "subCategories", "twoGisKeywords"})  // ← ОБЯЗАТЕЛЬНО
private BusinessCategory parentCategory;

@JsonIgnore   // ← ОБЯЗАТЕЛЬНО, иначе бесконечная рекурсия при сериализации
@OneToMany(mappedBy = "parentCategory")
private List<BusinessCategory> subCategories;

@Column(name = "two_gis_keywords", columnDefinition = "TEXT")
private String twoGisKeywords;  // "кофейня,кофе,coffee shop,кофе-бар"
Flutter — InfrastructureService и AnalyticsService — ИСПРАВЛЕННЫЙ ШАБЛОН

// ВСЕ сервисы должны использовать платформо-зависимый URL:
static String get _baseUrl {
  if (Platform.isAndroid) return 'http://10.0.2.2:8080';
  return 'http://127.0.0.1:8080'; // Windows Desktop / iOS симулятор
}
// Всегда добавлять JWT: options: Options(headers: {'Authorization': 'Bearer $token'})
// Всегда оборачивать в try-catch, возвращать [] или null при ошибке
Flutter — блок скоринга в property_details_screen.dart

// Три полоски (Локация УДАЛЕНА):
_scoreBar('Финансовый', scored.financialScore, 30),
_scoreBar('Технический', scored.technicalScore, 20),
_scoreBar('Конкуренты', scored.competitorScore, 50),

// Автозагрузка скоринга при открытии карточки с карты:
if (!widget.isLandlordMode && widget.scoredProperty == null) {
  _loadScore(); // → GET /api/properties/{id}/score
}

// Технические теги (быстрые чипы) в карточке помещения:
// powerKw, ceilingHeight, hasWater, hasVentilation, hasSeparateEntrance,
// hasWc, hasParking, hasLoadingZone, isOccupied
Flutter — AnalyticsDto теперь nullable

// analytics_screen.dart:
late Future<AnalyticsDto?> _analyticsFuture;
// При null показывает: 'Не удалось загрузить аналитику'
Flutter — CreateSearchProfileScreen, шаг 3 (Технические требования)

// Поля ввода: minPowerKw, minCeilingHeight
// Свитчи: requiresWater, requiresVentilation, requiresSeparateEntrance,
//          requiresWc, requiresParking, requiresLoadingZone
// Теги в карточке профиля: bolt, height, water_drop, air, door_front_door,
//                           wc, local_parking, local_shipping
5. На чём остановились
В последнем сеансе полностью завершена задача расширения технических характеристик:

Задача — Расширение технических характеристик помещений и скоринга
Property.java: добавлены hasWc, hasParking, hasLoadingZone.
SearchProfile.java: добавлены requiresWc, requiresParking, requiresLoadingZone, minCeilingHeight.
CreatePropertyRequest / CreateSearchProfileRequest: зеркально обновлены.
PropertyService.createProperty: новые поля включены в builder.
SearchProfileService: buildProfileFromRequest и updateSearchProfile обновлены.
PropertyScoringService.calculateTechnicalScore: переработан с 4 до 9 критериев (8 штрафов по требованиям + безусловный -1 за SHELL_AND_CORE). Импорт RepairState добавлен.
Flutter property.dart: добавлены hasWc, hasParking, hasLoadingZone, ceilingHeight в модель, конструктор и fromJson.
Flutter search_profile.dart: добавлены requiresWc, requiresParking, requiresLoadingZone, minCeilingHeight в модель, конструктор, fromJson и toJson.
Flutter search_profiles_screen.dart: шаг 3 расширен — поле minCeilingHeight (рядом с minPowerKw), 3 новых свитча; теги в карточке профиля дополнены; dispose обновлён.
Flutter property_details_screen.dart: секция быстрых тегов дополнена чипами высоты потолков, санузла, парковки, зоны разгрузки.
После рестарта бэкенда (gradle bootRun) Hibernate сам добавит 6 новых колонок в БД (has_wc, has_parking, has_loading_zone в properties; requires_wc, requires_parking, requires_loading_zone, min_ceiling_height в search_profiles).

6. Важные детали и договорённости
#	Деталь	Важность
1	2GIS принимает координаты как lon,lat (не lat,lon) в параметре point	Критично
2	spring.jpa.hibernate.ddl-auto=update — Hibernate сам добавляет/меняет столбцы при старте, Flyway не используется	Критично
3	@JsonIgnore на BusinessCategory.subCategories — без этого любой эндпоинт, возвращающий SearchProfile или Property с категорией, падает с StackOverflow	Критично
4	Матчинг рубрик 2GIS: однословные keyword — word-boundary (rubricWords.contains(kw)), многословные — substring (lowerRubric.contains(kw)). Предотвращает "бар" → "барбершоп"	Важно
5	Кэш-ключ 2GIS округляет координаты до 3 знаков (~111 м сетка) — соседние помещения делят один кэш-ответ	Важно
6	Рекомендательный список (GET /api/search-profiles/{id}/scored-properties) тоже вызывает 2GIS через scoreAndRankProperties() → scoreInternal() → calculateCompetitorScore()	Важно
7	DataInitializer запускается при каждом старте, но идемпотентен (findOrCreate)	Важно
8	В DataInitializer строка для "Бар" содержит trailing space: "бар " — нужно исправить	Баг (в коде есть, в БД уже исправлен TRIM)
9	Все Flutter-сервисы должны использовать Platform.isAndroid для выбора между 10.0.2.2 и 127.0.0.1	Важно
10	AnalyticsService.getMyAnalytics() возвращает AnalyticsDto? (nullable), экран аналитики это учитывает	Важно
11	Поле parking (String) в Property.java оставлено — не удалять, в БД могут быть данные. Новое булево поле hasParking добавлено отдельно	Важно
12	Технический скоринг — штрафная модель. Штраф за SHELL_AND_CORE (-1) безусловный, остальные — только если арендатор явно требует опцию	Важно
13	БД: myuser / mypassword / retail_aggregator / порт 5434	Справка
14	2GIS API ключ: 4864f04f-8983-435a-ae2e-06ed696ed550	Справка
7. Возможные следующие задачи
Исправить trailing space в DataInitializer для "Бар" — строка "паб,пивной бар,..." → убрать пробел перед закрывающей кавычкой
Добавить координаты центра поиска в профиль — сейчас форма не позволяет арендатору указать точку на карте (centerLatitude/centerLongitude), из-за чего радиусная часть не работает
Фото помещений — сейчас показывается только серый placeholder
Чат — файл chat_screen.dart существует, статус неизвестен
