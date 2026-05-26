# 03. Доменная модель

Документ описывает все JPA-сущности, их связи и репозитории. Это — «истина в последней инстанции» для понимания, какие данные хранятся в системе и как они связаны.

---

## 3.1. Карта сущностей

```
                     ┌──────────────┐
                     │     User     │ (implements UserDetails)
                     │              │
                     │  role        │
                     │  status      │
                     └──┬────────┬──┘
                        │ 1:1    │ 1:1
              ┌─────────┘        └─────────┐
              ▼                            ▼
     ┌────────────────┐          ┌──────────────────┐
     │ TenantProfile  │          │ LandlordProfile  │
     │  inn, phone    │          │  companyName,inn │
     │  targetCategory│          │  isVerified      │
     └────────┬───────┘          └──────────────────┘
              │                            ▲
              │ N:M (favorites)            │ 1:N (landlord)
              │                            │
              ▼                            │
     ┌────────────────────────────────────┴────────┐
     │                Property                     │
     │   address, lat/lon, area, price,            │
     │   propertyType, dealType, buildingClass,    │
     │   repairState, layout, accessType,          │
     │   heatingType, furnitureState,              │
     │   hasWater/Ventilation/Wc/...               │
     │   status (DRAFT/PUBLISHED/RENTED/ARCHIVED)  │
     └──┬──────┬─────────┬───────────┬──────────┬──┘
        │      │         │           │          │
        │1:N   │N:M      │1:N        │1:N       │1:N
        │      │         │           │          │
        ▼      ▼         ▼           ▼          ▼
   ┌─────────┐ ┌────────────────┐  ┌──────────┐ ┌──────────────┐
   │Property │ │BusinessCategory│  │ Property │ │  Favorite    │
   │ Image   │ │ (existing      │  │  View    │ │   Event      │
   │         │ │  Neighbors)    │  │  Event   │ │              │
   └─────────┘ └────────────────┘  └──────────┘ └──────────────┘
                       ▲
                       │ N:M (desired neighbors)
                       │
              ┌────────┴────────┐
              │  SearchProfile  │
              │  centerLat/Lon  │
              │  radiusMeters   │
              │  budget, area   │
              │  requires*      │
              └────────┬────────┘
                       │ 1:1 (target category)
                       ▼
              ┌─────────────────┐
              │BusinessCategory │ (иерархия parent → children)
              │  osmTags        │
              └─────────────────┘

Параллельно — каскад «заявка → чат-комната → сообщения»:

       Application ──── 1:1 ──── ChatRoom ──── 1:N ──── ChatMessage
           │                        │
           │                        ├── landlord (User)
           ├── property              │
           └── tenant (User)         └── tenant (User)

И отдельный «закэшированный» слой:

      OverpassCacheEntry  (snapshot Overpass-ответа в JSON)
      PropertyScoreSnapshot (готовый ScoredPropertyDto в JSON)
```

---

## 3.2. `User` — корневая сущность аутентификации

[`User.java`](../backend/src/main/java/com/example/backend/entity/User.java) | таблица **`users`**

```java
@Entity
@Table(name = "users")
public class User implements UserDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String email;

    @JsonIgnore
    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    @Enumerated(EnumType.STRING)
    private UserStatus status;

    @Column(name = "avatar_url")
    private String avatarUrl;

    @Column(name = "verification_code")
    @JsonIgnore
    private String verificationCode;

    @Column(name = "code_expires_at")
    @JsonIgnore
    private LocalDateTime codeExpiresAt;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    @JsonIgnore
    private LocalDateTime createdAt;

    @OneToOne(mappedBy = "user", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private TenantProfile tenantProfile;

    @OneToOne(mappedBy = "user", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private LandlordProfile landlordProfile;

    @ManyToMany
    @JoinTable(name = "favorites",
            joinColumns = @JoinColumn(name = "tenant_id"),
            inverseJoinColumns = @JoinColumn(name = "property_id"))
    private Set<Property> favoriteProperties = new HashSet<>();
}
```

### Поля

| Поле                 | Тип             | Constraints                  | Назначение                          |
|----------------------|-----------------|------------------------------|-------------------------------------|
| `id`                 | `Long`          | PK, IDENTITY                 | Первичный ключ                      |
| `email`              | `String`        | NOT NULL, UNIQUE             | Логин и канал верификации           |
| `passwordHash`       | `String`        | NOT NULL                     | BCrypt-хэш (JsonIgnore)             |
| `role`               | `Role` enum     | NOT NULL                     | TENANT / LANDLORD / ADMIN           |
| `status`             | `UserStatus`    | nullable                     | UNVERIFIED / ACTIVE / BANNED        |
| `avatarUrl`          | `String`        | nullable                     | URL аватара (`/uploads/avatars/...`)|
| `verificationCode`   | `String`        | nullable                     | 6-цифровой код, очищается после verify |
| `codeExpiresAt`      | `LocalDateTime` | nullable                     | TTL кода (2 мин с момента генерации) |
| `createdAt`          | `LocalDateTime` | NOT NULL, `@CreationTimestamp`| Аудит                              |

### Связи

- **`tenantProfile`** (1:1, `mappedBy="user"`, `CascadeType.ALL`) — профиль арендатора, если `role=TENANT`. Каскад удаления.
- **`landlordProfile`** (1:1, `mappedBy="user"`, `CascadeType.ALL`) — профиль арендодателя.
- **`favoriteProperties`** (N:M через `favorites`) — избранные помещения (только для TENANT, на уровне БД ограничения роли нет).

### Перечисления

[`Role`](../backend/src/main/java/com/example/backend/entity/enums/Role.java):
```java
public enum Role { TENANT, LANDLORD, ADMIN }
```

[`UserStatus`](../backend/src/main/java/com/example/backend/entity/enums/UserStatus.java):
```java
public enum UserStatus { UNVERIFIED, ACTIVE, BANNED }
```

Маппинг в Spring Security и переходы статусов — в [02-security-and-auth.md](02-security-and-auth.md).

### Репозиторий

[`UserRepository.java`](../backend/src/main/java/com/example/backend/repository/UserRepository.java):
```java
public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);
    boolean existsByEmail(String email);
}
```

---

## 3.3. `TenantProfile` — профиль арендатора

[`TenantProfile.java`](../backend/src/main/java/com/example/backend/entity/TenantProfile.java) | таблица **`tenant_profiles`**

```java
@Entity
@Table(name = "tenant_profiles")
public class TenantProfile {

    @Id
    @Column(name = "user_id")
    private Long id;

    @OneToOne
    @MapsId
    @JoinColumn(name = "user_id")
    @JsonIgnore
    private User user;

    private String name;

    @Column(unique = true)
    private String inn;

    private String phone;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "target_business_category_id")
    private BusinessCategory targetBusinessCategory;

    @Transient
    private String avatarUrl;
}
```

### Особенности

- **`@MapsId`** — PK таблицы равен `user_id`. Это «shared primary key» pattern: один пользователь = один профиль; нет отдельного auto-increment id. На уровне БД это означает: `tenant_profiles.user_id` одновременно PK и FK к `users.id`.
- **`inn` UNIQUE** — два разных арендатора не могут иметь один и тот же ИНН (см. `AuthService.register`).
- **`targetBusinessCategory`** — категория бизнеса, который арендатор планирует открыть. Опциональное поле, используется как дефолтный фильтр.
- **`avatarUrl @Transient`** — не хранится в `tenant_profiles`, заполняется при чтении из `User.avatarUrl` (см. `ProfileService.getTenantProfile`). Это сделано чтобы в DTO арендатора было поле `avatarUrl`, но физически оно живёт в `users.avatar_url`.

### Репозиторий

[`TenantProfileRepository.java`](../backend/src/main/java/com/example/backend/repository/TenantProfileRepository.java):
```java
public interface TenantProfileRepository extends JpaRepository<TenantProfile, Long> {
    Optional<TenantProfile> findByInn(String inn);
}
```

---

## 3.4. `LandlordProfile` — профиль арендодателя

[`LandlordProfile.java`](../backend/src/main/java/com/example/backend/entity/LandlordProfile.java) | таблица **`landlord_profiles`**

```java
@Entity
@Table(name = "landlord_profiles")
public class LandlordProfile {

    @Id
    @Column(name = "user_id")
    private Long id;

    @OneToOne
    @MapsId
    @JoinColumn(name = "user_id")
    @JsonIgnore
    private User user;

    @Column(name = "company_name")
    private String companyName;

    private String inn;
    private String phone;

    @Column(name = "is_verified")
    private Boolean isVerified;

    @Transient
    private String avatarUrl;
}
```

### Отличия от `TenantProfile`

- **`companyName`** вместо `name` — арендодатель чаще всего юрлицо/ИП.
- **`isVerified`** — флаг ручной верификации админом (например, проверка ОГРН/документов). По умолчанию `false`, в текущем UI не используется в фильтрах, но заложен.
- **`inn` без `@Column(unique = true)`** — отличие от `TenantProfile`. Проверка уникальности есть в коде (`AuthService.register`), но не на уровне БД constraint'a.

---

## 3.5. `Property` — главная сущность каталога

[`Property.java`](../backend/src/main/java/com/example/backend/entity/Property.java) | таблица **`properties`**

Самая большая сущность в системе — 36 полей, объединённых в 6 смысловых блоков.

```java
@Entity
@Table(name = "properties")
public class Property {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "landlord_id", nullable = false)
    private User landlord;

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description;

    private String address;

    @Column(precision = 10, scale = 8)
    private BigDecimal latitude;

    @Column(precision = 11, scale = 8)
    private BigDecimal longitude;

    @Column(name = "area_sqm", precision = 10, scale = 2)
    private BigDecimal areaSqm;

    @Column(name = "price_per_month", precision = 12, scale = 2)
    private BigDecimal pricePerMonth;

    @Enumerated(EnumType.STRING)
    private PropertyStatus status;

    // --- 1. Базовая информация ---
    @Enumerated(EnumType.STRING) private PropertyType propertyType;
    @Enumerated(EnumType.STRING) private DealType dealType;
    private String buildingName;
    @Enumerated(EnumType.STRING) private BuildingClass buildingClass;
    private Integer floor;
    private Integer totalFloors;
    private Integer buildYear;

    // --- 2. Финансовые условия ---
    private Boolean taxIncluded;
    private Boolean opexIncluded;
    private Boolean utilityIncluded;
    private Integer depositMonths;
    private Boolean rentHolidays;
    private Boolean legalAddressProvided;

    // --- 3. Локация и доступность ---
    private String metroStation;
    private Integer timeToMetro; // в минутах

    // --- 4. Технические характеристики ---
    @Column(name = "power_kw")        private Integer powerKw;
    @Column(name = "has_water")        private Boolean hasWater;
    @Column(name = "has_ventilation")  private Boolean hasVentilation;
    @Column(name = "has_separate_entrance") private Boolean hasSeparateEntrance;
    @Enumerated(EnumType.STRING) private RepairState repairState;
    @Column(precision = 4, scale = 2)  private BigDecimal ceilingHeight;
    @Enumerated(EnumType.STRING)       private LayoutType layout;

    // --- 5. Инфраструктура ---
    private String parking;
    private String security;
    @Column(name = "has_wc")           private Boolean hasWc;
    @Column(name = "has_parking")      private Boolean hasParking;
    @Column(name = "has_loading_zone") private Boolean hasLoadingZone;

    // --- 6. Контакты ---
    private String contactName;
    private String contactPhone;

    @Column(precision = 5, scale = 2)
    private BigDecimal agentFee; // % комиссии

    @OneToMany(mappedBy = "property", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PropertyImage> images;

    @ManyToMany
    @JoinTable(name = "property_existing_neighbors",
            joinColumns = @JoinColumn(name = "property_id"),
            inverseJoinColumns = @JoinColumn(name = "category_id"))
    private Set<BusinessCategory> existingNeighbors;

    private String cadastralNumber;

    @Enumerated(EnumType.STRING) private AccessType accessType;
    @Enumerated(EnumType.STRING) private HeatingType heatingType;
    @Enumerated(EnumType.STRING) private FurnitureState furnitureState;

    @Column(name = "is_occupied")
    private Boolean isOccupied;
}
```

### 3.5.1. Поля по блокам

#### Идентификация и владение
| Поле       | Назначение                                                          |
|------------|---------------------------------------------------------------------|
| `id`       | PK                                                                  |
| `landlord` | `@ManyToOne User` — владелец объявления, обязателен                 |
| `title`    | Краткое название, NOT NULL                                          |
| `description` | TEXT-описание                                                    |
| `status`   | `PropertyStatus` — DRAFT / PUBLISHED / RENTED / ARCHIVED            |

#### Геолокация
| Поле        | Тип                       | Особенности                                              |
|-------------|---------------------------|----------------------------------------------------------|
| `address`   | `String`                  | Текстовый адрес                                          |
| `latitude`  | `BigDecimal(10,8)`        | ±90.00000000 (8 знаков ≈ 1 мм точности)                  |
| `longitude` | `BigDecimal(11,8)`        | ±180.00000000                                            |

`BigDecimal` вместо `Double` — гарантия точности при хранении координат, без округлений float'a.

#### Финансы
| Поле                   | Тип             | Назначение                                  |
|------------------------|-----------------|---------------------------------------------|
| `areaSqm`              | `BigDecimal(10,2)` | Площадь в м²                            |
| `pricePerMonth`        | `BigDecimal(12,2)` | Аренда в ₽/мес                          |
| `taxIncluded`          | `Boolean`       | Включает ли цена налог                      |
| `opexIncluded`         | `Boolean`       | Операционные расходы включены               |
| `utilityIncluded`      | `Boolean`       | Коммуналка включена                         |
| `depositMonths`        | `Integer`       | Залог в месяцах                             |
| `rentHolidays`         | `Boolean`       | Арендные каникулы                           |
| `legalAddressProvided` | `Boolean`       | Можно ли зарегистрировать юрадрес           |
| `agentFee`             | `BigDecimal(5,2)`| Комиссия агента в %                        |

#### Тип здания и помещения
| Поле             | Enum                                                                  |
|------------------|-----------------------------------------------------------------------|
| `propertyType`   | `PropertyType` — OFFICE / RETAIL / WAREHOUSE / PRODUCTION / PSN / CATERING |
| `dealType`       | `DealType` — DIRECT_LEASE / SUBLEASE                                  |
| `buildingClass`  | `BuildingClass` — A / B / B_PLUS / C / D                              |
| `layout`         | `LayoutType` — OPEN_SPACE / CABINET / MIXED                           |
| `accessType`     | `AccessType` — FREE / SCHEDULE / PASS                                 |
| `heatingType`    | `HeatingType` — CENTRAL / AUTONOMOUS / NONE                           |
| `furnitureState` | `FurnitureState` — EMPTY / FURNISHED / READY_BUSINESS                 |
| `repairState`    | `RepairState` — SHELL_AND_CORE / TYPICAL / DESIGNER / PRE_FINISHING   |

Все enum'ы хранятся как `EnumType.STRING` — читаемые значения в БД, не порядковые. Это даёт устойчивость к перестановке/добавлению значений в enum'е.

#### Технические характеристики
| Поле                  | Тип                  | Что значит                              |
|-----------------------|----------------------|-----------------------------------------|
| `powerKw`             | `Integer`            | Электрическая мощность, кВт             |
| `hasWater`            | `Boolean`            | Водоснабжение                           |
| `hasVentilation`      | `Boolean`            | Вытяжка/принудительная вентиляция       |
| `hasSeparateEntrance` | `Boolean`            | Отдельный вход с улицы                  |
| `ceilingHeight`       | `BigDecimal(4,2)`    | Высота потолков, м                      |
| `hasWc`               | `Boolean`            | Санузел                                 |
| `hasParking`          | `Boolean`            | Парковка                                |
| `hasLoadingZone`      | `Boolean`            | Зона разгрузки                          |

Каждое из этих полей участвует в техническом скоринге (`PropertyScoringService.calculateTechnical`, см. [04-services-business-logic.md](04-services-business-logic.md) §4.2).

#### Прочее
| Поле              | Назначение                                                 |
|-------------------|------------------------------------------------------------|
| `floor`           | Этаж                                                       |
| `totalFloors`     | Всего этажей в здании                                      |
| `buildYear`       | Год постройки                                              |
| `metroStation`    | Название ближайшей станции (текстом, для отображения)      |
| `timeToMetro`     | Минут пешком до метро (заявлено арендодателем)             |
| `parking`         | Текстовое описание парковки                                |
| `security`        | Текстовое описание охраны                                  |
| `cadastralNumber` | Кадастровый номер для юридической проверки                 |
| `contactName`     | Имя контактного лица (может отличаться от арендодателя)    |
| `contactPhone`    | Телефон для связи                                          |
| `isOccupied`      | Сейчас занято / свободно                                   |

### 3.5.2. Связи

- **`landlord`** (`@ManyToOne`, `LAZY`, NOT NULL) — владелец.
- **`images`** (`@OneToMany`, `cascade=ALL`, `orphanRemoval=true`) — фотографии. Удаление property каскадно удаляет картинки.
- **`existingNeighbors`** (`@ManyToMany` через `property_existing_neighbors`) — категории бизнесов, которые **уже есть в этом здании/комплексе** (заявлено landlord'ом). Используется в фильтре `findRecommendedPropertiesWithoutCompetitors`.

### 3.5.3. `PropertyStatus` lifecycle

[`PropertyStatus.java`](../backend/src/main/java/com/example/backend/entity/enums/PropertyStatus.java):

```java
public enum PropertyStatus { DRAFT, PUBLISHED, RENTED, ARCHIVED }
```

Переходы:

```
                ┌──────────────────────────────────┐
DRAFT ─────────►│ PUBLISHED ── createProperty()    │
                │     │                            │
                │     │ ApplicationService.update  │
                │     │ Status(ACCEPTED)           │
                │     ▼                            │
                │ RENTED                           │
                │     │                            │
                │     │ (нет автоматического       │
                │     │  возврата в PUBLISHED)     │
                │     ▼                            │
                │ ARCHIVED ◄── deleteProperty()    │
                └──────────────────────────────────┘
```

- **`DRAFT`** — задано в enum'е, но в текущем коде новые помещения создаются сразу как `PUBLISHED` (см. `PropertyService.createProperty`). Зарезервировано.
- **`PUBLISHED`** — видно в листинге, на карте, в скоринге.
- **`RENTED`** — автоматически переводится при `ApplicationService.updateApplicationStatus(ACCEPTED)`. Помещение больше не отображается арендаторам как доступное.
- **`ARCHIVED`** — soft-delete. `PropertyService.deleteProperty` ставит статус `ARCHIVED` (не делает реальный `DELETE`). Аналитика по `AnalyticsService.getLandlordAnalytics` фильтрует архивные.

### 3.5.4. Репозиторий

[`PropertyRepository.java`](../backend/src/main/java/com/example/backend/repository/PropertyRepository.java):

```java
public interface PropertyRepository extends JpaRepository<Property, Long> {

    @Query("SELECT p FROM User u JOIN u.favoriteProperties p WHERE u.id = :tenantId")
    List<Property> findFavoritePropertiesByTenantId(@Param("tenantId") Long tenantId);

    List<Property> findByLandlordId(Long landlordId);
    List<Property> findByStatus(PropertyStatus status);

    @Query("SELECT p FROM Property p WHERE p.status = 'PUBLISHED' AND :category NOT MEMBER OF p.existingNeighbors")
    List<Property> findRecommendedPropertiesWithoutCompetitors(@Param("category") BusinessCategory category);

    List<Property> findByStatusAndHasSeparateEntranceTrueAndHasVentilationTrue(PropertyStatus status);
}
```

- **`findFavoritePropertiesByTenantId`** — JPQL JOIN через many-to-many `favorites`. Один query вместо ленивой загрузки `user.favoriteProperties`.
- **`findRecommendedPropertiesWithoutCompetitors`** — JPQL `NOT MEMBER OF`. Отдаёт PUBLISHED-помещения, в которых нет категории арендатора среди `existingNeighbors`. Используется в простом фильтре «без прямых соседей-конкурентов» (не путать с географическим скорингом).

---

## 3.6. `BusinessCategory` — иерархия категорий бизнеса

[`BusinessCategory.java`](../backend/src/main/java/com/example/backend/entity/BusinessCategory.java) | таблица **`business_categories`**

```java
@Entity
@Table(name = "business_categories")
public class BusinessCategory {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "parent_id")
    @JsonIgnoreProperties({"parentCategory", "subCategories", "osmTags"})
    private BusinessCategory parentCategory;

    @JsonIgnore
    @OneToMany(mappedBy = "parentCategory")
    private List<BusinessCategory> subCategories;

    /**
     * OSM key=value-теги, по которым категория сопоставляется с результатами
     * Overpass API. CSV, нижний регистр. Пример: "amenity=pharmacy,shop=chemist".
     *
     * Колонка БД называется search_keywords по историческим причинам
     * (раньше тут лежали ключевые слова для Yandex Places API).
     */
    @Column(name = "search_keywords", columnDefinition = "TEXT")
    private String osmTags;
}
```

### Иерархия

Self-referencing `parent_id` → одна таблица хранит и корневые, и листовые категории. Корневых — 5, листовых — 30 (см. [01-architecture-and-infrastructure.md §1.7.5](01-architecture-and-infrastructure.md)). Заполняется `DataInitializer` при старте.

### OSM-теги

Ключевое поле для скоринга. Каждой листовой категории сопоставлен CSV OSM-тегов формата `key=value`:

| Категория        | osmTags                                                              |
|------------------|----------------------------------------------------------------------|
| Аптека           | `amenity=pharmacy,healthcare=pharmacy,shop=chemist`                  |
| Кофейня          | `amenity=cafe,shop=coffee`                                           |
| Продуктовый магазин | `shop=supermarket,shop=convenience,shop=grocery,shop=greengrocer,shop=general` |
| ПВЗ              | `shop=parcel_locker,amenity=parcel_locker,amenity=post_office,office=courier,amenity=post_depot` |

В рантайме `PropertyScoringService.buildTagIndex` строит inverted-индекс `tag → List<BusinessCategory>`:

```java
private Map<String, List<BusinessCategory>> buildTagIndex(List<BusinessCategory> categories) {
    Map<String, List<BusinessCategory>> index = new HashMap<>();
    for (BusinessCategory cat : categories) {
        String csv = cat.getOsmTags();
        if (csv == null || csv.isBlank()) continue;
        for (String raw : csv.split(",")) {
            String tag = raw.trim().toLowerCase();
            if (tag.isEmpty() || !tag.contains("=")) continue;
            index.computeIfAbsent(tag, k -> new ArrayList<>()).add(cat);
        }
    }
    return index;
}
```

Затем Overpass возвращает POI с тегами вроде `amenity=pharmacy`, и индекс мгновенно говорит: «это категория Аптека (id=12) или её родитель Красота и здоровье».

### `@JsonIgnoreProperties` на parent

Для предотвращения бесконечной рекурсии при сериализации (parent → category → parent → ...). При выводе DTO category-tree мы ходим только сверху вниз (через `subCategories`), а `parentCategory` сериализуется без раскрытия его связей.

### Репозиторий

[`BusinessCategoryRepository.java`](../backend/src/main/java/com/example/backend/repository/BusinessCategoryRepository.java):
```java
public interface BusinessCategoryRepository extends JpaRepository<BusinessCategory, Long> {
    List<BusinessCategory> findByParentCategoryIsNull();   // корневые
    Optional<BusinessCategory> findByName(String name);    // для идемпотентности DataInitializer
}
```

---

## 3.7. `SearchProfile` — проект поиска арендатора

[`SearchProfile.java`](../backend/src/main/java/com/example/backend/entity/SearchProfile.java) | таблица **`search_profiles`**

Это «сохранённый поиск» арендатора. Один арендатор может иметь несколько проектов («Открыть кофейню на Арбате», «Аптека в Митино»), каждый с независимыми критериями. Активный профиль определяет, как для арендатора будет посчитан скоринг рекомендованных помещений.

```java
@Entity
@Table(name = "search_profiles")
public class SearchProfile {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    private User tenant;

    @Column(nullable = false)
    private String name; // "Открыть кофейню на Арбате"

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "business_category_id")
    private BusinessCategory businessCategory;

    // --- 1. Финансовые критерии (20% скоринга) ---
    @Column(name = "min_area", precision = 10, scale = 2)  private BigDecimal minArea;
    @Column(name = "max_area", precision = 10, scale = 2)  private BigDecimal maxArea;
    @Column(name = "min_budget", precision = 12, scale = 2) private BigDecimal minBudget;
    @Column(name = "max_budget", precision = 12, scale = 2) private BigDecimal maxBudget;

    // --- 2. Технические критерии (20% скоринга) ---
    @Column(name = "min_power_kw") private Integer minPowerKw;
    @Column(name = "requires_water") private Boolean requiresWater;
    @Column(name = "requires_ventilation") private Boolean requiresVentilation;
    @Column(name = "requires_separate_entrance") private Boolean requiresSeparateEntrance;
    @Column(name = "requires_wc") private Boolean requiresWc;
    @Column(name = "requires_parking") private Boolean requiresParking;
    @Column(name = "requires_loading_zone") private Boolean requiresLoadingZone;
    @Column(name = "min_ceiling_height", precision = 4, scale = 2) private BigDecimal minCeilingHeight;

    // --- 3. Локация и синергия (25% + 15% + 5% скоринга) ---
    @Column(name = "center_latitude", precision = 10, scale = 8)  private BigDecimal centerLatitude;
    @Column(name = "center_longitude", precision = 11, scale = 8) private BigDecimal centerLongitude;
    @Column(name = "search_radius_meters")  private Integer searchRadiusMeters;
    @Column(name = "synergy_radius_meters") private Integer synergyRadiusMeters;

    // Категории желаемых соседей
    @ManyToMany
    @JoinTable(name = "search_profile_desired_neighbors",
            joinColumns = @JoinColumn(name = "search_profile_id"),
            inverseJoinColumns = @JoinColumn(name = "category_id"))
    private Set<BusinessCategory> desiredNeighbors;

    @Column(name = "is_active")
    @Builder.Default
    private Boolean isActive = true;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
```

### Маппинг полей на скоринг

| Группа полей      | Куда идёт в `PropertyScoringService`         | Макс. балл |
|-------------------|----------------------------------------------|------------|
| `minBudget`, `maxBudget`, `minArea`, `maxArea` | `calculateFinancial`         | 0–20 |
| `requiresWater`, `requiresVentilation`, `requiresSeparateEntrance`, `requiresWc`, `requiresParking`, `requiresLoadingZone`, `minPowerKw`, `minCeilingHeight` | `calculateTechnical` | 0–20 |
| `businessCategory` (target), `searchRadiusMeters` | `analyzeNeighborhood` → «прямые конкуренты»  | 0–40 |
| `desiredNeighbors`, `synergyRadiusMeters` | `analyzeNeighborhood` → «синергия»          | 0–15 |
| (фиксировано 1500м, не из профиля) | `calculateTransport`                        | 0–5  |

### `searchRadiusMeters` vs `synergyRadiusMeters`

Два независимых радиуса:
- **`searchRadiusMeters`** — радиус анализа **прямых конкурентов**. По умолчанию используется и для синергии (для обратной совместимости со старыми профилями).
- **`synergyRadiusMeters`** — радиус анализа **желаемых соседей**. Если задан, переопределяет первый специально для синергии.

В коде `PropertyScoringService.fetchAreaSnapshot`:
```java
int competitorRadius = profile.getSearchRadiusMeters() != null
        ? Math.min(profile.getSearchRadiusMeters(), 5000)
        : 1000;
int synergyRadius = profile.getSynergyRadiusMeters() != null
        ? Math.min(profile.getSynergyRadiusMeters(), 5000)
        : competitorRadius;
int radius = Math.max(Math.max(competitorRadius, synergyRadius), TRANSPORT_SEARCH_RADIUS_METERS);
```

Hard-cap **5 км** на оба — защита от случайных огромных значений, которые бы съели Overpass.

### `desiredNeighbors` (синергия)

`@ManyToMany` через `search_profile_desired_neighbors`. Категории бизнеса, **рядом с которыми** арендатор хочет открыться (например, кофейня хочет быть рядом с университетами и бизнес-центрами).

### Репозиторий

[`SearchProfileRepository.java`](../backend/src/main/java/com/example/backend/repository/SearchProfileRepository.java):
```java
public interface SearchProfileRepository extends JpaRepository<SearchProfile, Long> {
    List<SearchProfile> findByTenantId(Long tenantId);
    List<SearchProfile> findByTenantIdAndIsActiveTrue(Long tenantId);
}
```

`findByTenantIdAndIsActiveTrue` используется в `PropertyService.getRecommendedPropertiesForTenant` для определения «текущего активного проекта» арендатора.

---

## 3.8. `Application` — заявка на аренду

[`Application.java`](../backend/src/main/java/com/example/backend/entity/Application.java) | таблица **`applications`**

```java
@Entity
@Table(name = "applications")
public class Application {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    private Property property;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    private User tenant;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ApplicationStatus status;

    @Column(name = "cover_letter", columnDefinition = "TEXT")
    private String coverLetter;

    @Column(name = "rejection_reason", columnDefinition = "TEXT")
    private String rejectionReason;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
```

### Lifecycle

[`ApplicationStatus.java`](../backend/src/main/java/com/example/backend/entity/enums/ApplicationStatus.java):
```java
public enum ApplicationStatus { PENDING, REVIEWING, ACCEPTED, REJECTED }
```

```
                createApplication                updateApplicationStatus
                       │                                  │
arendator   ──► PENDING ──► REVIEWING ──► ACCEPTED  ──► (Property.status=RENTED, ChatRoom создаётся)
                       │           │
                       │           └─► REJECTED (rejection_reason заполняется)
                       │
                       └─► REJECTED (без REVIEWING)
```

- **PENDING** — арендатор подал, арендодатель не смотрел.
- **REVIEWING** — арендодатель открыл/начал обработку.
- **ACCEPTED** — принята; `Property.status` автоматически переводится в `RENTED` (см. `ApplicationService.updateApplicationStatus`).
- **REJECTED** — отклонена; обязательно с `rejectionReason`.

### Правила и проверки

- Можно подавать только на `PUBLISHED` помещение.
- Удалять можно только не-`ACCEPTED` заявки (на принятой висит реальная аренда).
- При создании заявки → push-уведомление landlord'у (`NotificationService`).
- При смене статуса → push-уведомление tenant'у.

### Репозиторий

[`ApplicationRepository.java`](../backend/src/main/java/com/example/backend/repository/ApplicationRepository.java):
```java
public interface ApplicationRepository extends JpaRepository<Application, Long> {
    List<Application> findByTenantId(Long tenantId);
    List<Application> findByProperty_LandlordId(Long landlordId);
    List<Application> findByPropertyId(Long propertyId);

    List<Application> findByPropertyIdAndCreatedAtAfter(Long propertyId, LocalDateTime date);
    List<Application> findByProperty_LandlordIdAndCreatedAtAfter(Long landlordId, LocalDateTime date);
}
```

`findByProperty_LandlordId` — через nested property: Spring Data JPA генерирует `JOIN properties p ON a.property_id=p.id WHERE p.landlord_id=?`.

---

## 3.9. `ChatRoom` и `ChatMessage` — чат

### ChatRoom

[`ChatRoom.java`](../backend/src/main/java/com/example/backend/entity/ChatRoom.java) | таблица **`chat_rooms`**

```java
@Entity
@Table(name = "chat_rooms")
public class ChatRoom {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "application_id", nullable = false)
    private Application application;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "landlord_id", nullable = false)
    private User landlord;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    private User tenant;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
```

- Одна заявка → одна комната (1:1 через `application_id`).
- Денормализованные `landlord_id` и `tenant_id` (хотя их можно получить через `application.property.landlord` и `application.tenant`) — это ускоряет запросы вроде «все комнаты, где я landlord ИЛИ tenant» (`findByLandlordIdOrTenantId`).

### ChatMessage

[`ChatMessage.java`](../backend/src/main/java/com/example/backend/entity/ChatMessage.java) | таблица **`chat_messages`**

```java
@Entity
@Table(name = "chat_messages")
public class ChatMessage {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "chat_room_id", nullable = false)
    private ChatRoom chatRoom;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "sender_id", nullable = false)
    private User sender;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String content;

    @Column(name = "is_read")
    private boolean isRead;

    @CreationTimestamp
    @Column(name = "timestamp", updatable = false)
    private LocalDateTime timestamp;
}
```

- `is_read` — boolean (примитив, не Boolean), default `false`. Текущая логика помечает прочитанным только сторону получателя при чтении (см. контроллер `ChatController`).
- `timestamp` — `@CreationTimestamp` (сервер-сайд).

### Репозитории

[`ChatRoomRepository.java`](../backend/src/main/java/com/example/backend/repository/ChatRoomRepository.java):
```java
public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {
    Optional<ChatRoom> findByApplicationId(Long applicationId);
    List<ChatRoom> findByLandlordIdOrTenantId(Long landlordId, Long tenantId);

    @Query("SELECT COUNT(DISTINCT c.tenant.id) FROM ChatRoom c WHERE c.landlord.id = :landlordId")
    long countDistinctTenantsByLandlordId(@Param("landlordId") Long landlordId);
}
```

[`ChatMessageRepository.java`](../backend/src/main/java/com/example/backend/repository/ChatMessageRepository.java):
```java
public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {
    List<ChatMessage> findByChatRoomIdOrderByTimestampAsc(Long chatRoomId);
}
```

---

## 3.10. `PropertyImage` — фотографии помещения

[`PropertyImage.java`](../backend/src/main/java/com/example/backend/entity/PropertyImage.java) | таблица **`property_images`**

```java
@Entity
@Table(name = "property_images")
@ToString(exclude = "property")
@EqualsAndHashCode(exclude = "property")
public class PropertyImage {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JsonIgnore
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    private Property property;

    @Column(name = "image_url", nullable = false)
    private String imageUrl;

    @Column(name = "is_main")
    private Boolean isMain;
}
```

- `imageUrl` — относительный путь вида `/uploads/properties/{propertyId}/{uuid}.jpg`. Реальный файл лежит на ФС в `app.upload.dir`, отдаётся через `WebMvcConfig`.
- `isMain` — главная фотография (показывается в карточке списка). Логика: при upload первой фото — `isMain=true`; при удалении главной — следующая первая становится главной (`PropertyImageService.delete`).
- `@ToString(exclude="property")` и `@EqualsAndHashCode(exclude="property")` — обязательны, иначе Lombok-сгенерированный `toString()` зайдёт в цикл `Property↔PropertyImage`.

**Лимит:** `PropertyImageService.MAX_IMAGES_PER_PROPERTY = 10`.

### Репозиторий

```java
public interface PropertyImageRepository extends JpaRepository<PropertyImage, Long> {
    List<PropertyImage> findByPropertyId(Long propertyId);
}
```

---

## 3.11. Аналитические события

### PropertyViewEvent

[`PropertyViewEvent.java`](../backend/src/main/java/com/example/backend/entity/PropertyViewEvent.java) | таблица **`property_view_events`**

```java
@Entity
@Table(name = "property_view_events")
public class PropertyViewEvent {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    private Property property;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "viewer_id") // Nullable: anonymous views
    private User viewer;

    @CreationTimestamp
    @Column(name = "view_timestamp", updatable = false)
    private LocalDateTime viewTimestamp;
}
```

- Логируется при `GET /api/properties/{id}` (см. `PropertyController` + `AnalyticsService.logPropertyView`).
- `viewer` nullable — анонимные просмотры (когда нет JWT) учитываются как отдельные события (нечем сгруппировать).
- При выводе landlord-аналитики авторизованные просмотры **дедуплицируются** по паре `(property, viewer)` — повторное открытие одной карточки одним пользователем не разгоняет счётчик (см. `AnalyticsService.dedupeViewsByViewer`).

### FavoriteEvent

[`FavoriteEvent.java`](../backend/src/main/java/com/example/backend/entity/FavoriteEvent.java) | таблица **`favorite_events`**

```java
@Entity
@Table(name = "favorite_events")
public class FavoriteEvent {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    private Property property;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id")
    private User tenant;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
```

- Логируется ровно при **добавлении** в избранное (см. `PropertyService.addFavorite` → `AnalyticsService.logFavoriteEvent`). Удаление **не** логируется — для аналитики важен факт интереса, а не последующий отказ.
- Связь с фактическими избранными — через таблицу `favorites` (many-to-many `User.favoriteProperties`). `FavoriteEvent` — это event log, `favorites` — текущее состояние.

### Репозитории

```java
public interface PropertyViewEventRepository extends JpaRepository<PropertyViewEvent, Long> {
    List<PropertyViewEvent> findByPropertyLandlordIdAndViewTimestampAfter(Long landlordId, LocalDateTime date);
    List<PropertyViewEvent> findByPropertyIdAndViewTimestampAfter(Long propertyId, LocalDateTime date);
}

public interface FavoriteEventRepository extends JpaRepository<FavoriteEvent, Long> {
    List<FavoriteEvent> findByPropertyLandlordIdAndCreatedAtAfter(Long landlordId, LocalDateTime date);
    List<FavoriteEvent> findByPropertyIdAndCreatedAtAfter(Long propertyId, LocalDateTime date);
}
```

`findByPropertyLandlordId...` — nested property navigation: Spring Data сам генерирует JOIN на `properties`.

---

## 3.12. Кэширующие сущности

### 3.12.1. `OverpassCacheEntry` — L2-кэш OSM-снимков

[`OverpassCacheEntry.java`](../backend/src/main/java/com/example/backend/entity/OverpassCacheEntry.java) | таблица **`overpass_cache`**

```java
@Entity
@Table(name = "overpass_cache",
        indexes = @Index(name = "idx_overpass_cache_key", columnList = "cache_key", unique = true))
public class OverpassCacheEntry {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "cache_key", nullable = false, unique = true, length = 64)
    private String cacheKey;

    @Column(name = "response_json", nullable = false, columnDefinition = "TEXT")
    private String responseJson;

    @Column(name = "cached_at", nullable = false)
    private LocalDateTime cachedAt;
}
```

### Структура ключа

```java
private String buildCacheKey(double lat, double lon, int radiusMeters) {
    long latKey = Math.round(lat * 1000);          // ~111 м точности по широте
    long lonKey = Math.round(lon * 1000);          // на широте Москвы ~67 м по долготе
    int radiusBucket = Math.floorDiv(radiusMeters, 250);
    return latKey + "_" + lonKey + "_" + radiusBucket;
}
```

Пример: для (55.7558, 37.6173) и радиуса 1000 м → ключ `"55756_37617_4"`. Адреса в одном квартале → одинаковый bucket → переиспользуют кэш.

### Что хранится в `responseJson`

Сериализованный `OverpassAreaSnapshot` (см. [`OverpassAreaSnapshot.java`](../backend/src/main/java/com/example/backend/service/OverpassAreaSnapshot.java)):

```java
public record OverpassAreaSnapshot(
        List<NearbyBusiness> businesses,
        List<TransportStop> transportStops,
        FetchStatus status
) { /* ... */ }
```

При сохранении (`OverpassPersistentCache.put`):
- **FAILED не кэшируется** — иначе временный сбой Overpass «прибьёт» точку на 7 дней.
- Только `OK`-снимки.

### TTL

`overpass.cache.ttl-hours=168` (7 дней). При чтении сервис игнорирует записи старше cutoff. Cleanup'ом устаревших занимается `@Scheduled` cron на 03:00.

### Репозиторий

[`OverpassCacheRepository.java`](../backend/src/main/java/com/example/backend/repository/OverpassCacheRepository.java):
```java
public interface OverpassCacheRepository extends JpaRepository<OverpassCacheEntry, Long> {

    Optional<OverpassCacheEntry> findByCacheKey(String cacheKey);

    @Modifying
    @Query("DELETE FROM OverpassCacheEntry e WHERE e.cachedAt < :cutoff")
    int deleteByCachedAtBefore(@Param("cutoff") LocalDateTime cutoff);
}
```

### 3.12.2. `PropertyScoreSnapshot` — L3-кэш готовых оценок

[`PropertyScoreSnapshot.java`](../backend/src/main/java/com/example/backend/entity/PropertyScoreSnapshot.java) | таблица **`property_score_snapshots`**

```java
@Entity
@Table(name = "property_score_snapshots",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_score_snapshot_property_profile_ver",
                columnNames = {"property_id", "profile_id", "algorithm_version"}),
        indexes = @Index(name = "idx_score_snapshot_lookup",
                columnList = "property_id,profile_id,algorithm_version"))
public class PropertyScoreSnapshot {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "property_id", nullable = false)
    private Long propertyId;

    @Column(name = "profile_id")
    private Long profileId;

    @Column(name = "algorithm_version", nullable = false, length = 16)
    private String algorithmVersion;

    @Column(name = "total_score", nullable = false)
    private int totalScore;

    @Column(name = "financial_score", nullable = false)
    private int financialScore;

    @Column(name = "technical_score", nullable = false)
    private int technicalScore;

    @Column(name = "competitor_score", nullable = false)
    private int competitorScore;

    @Column(name = "synergy_score", nullable = false)
    private int synergyScore;

    @Column(name = "transport_score", nullable = false)
    private int transportScore;

    @Column(name = "match_label", length = 128)
    private String matchLabel;

    @Column(name = "match_color", length = 16)
    private String matchColor;

    @Column(name = "data_status", nullable = false, length = 32)
    private String dataStatus;

    @Column(name = "payload_json", nullable = false, columnDefinition = "TEXT")
    private String payloadJson;

    @Column(name = "computed_at", nullable = false)
    private LocalDateTime computedAt;
}
```

### Ключевые особенности

1. **Composite unique key (`property_id`, `profile_id`, `algorithm_version`).** Под одну пару (помещение, профиль) и текущую версию алгоритма — ровно одна актуальная оценка. Если алгоритм изменился — старая запись инвалидируется, новая записывается без конфликта.
2. **Денормализация баллов.** Все компонентные scores (financial, technical, competitor, synergy, transport) и итоговый total хранятся отдельными колонками, плюс полный DTO в `payload_json`. Это даёт возможность будущих запросов вроде «топ-10 помещений по общему скору без чтения JSON» — но в текущем коде используется только `payload_json`.
3. **`payload_json`** — это сериализованный `ScoredPropertyDto` **без поля `property`** (heavy-объект с картинками и владельцем). При восстановлении (`PropertyScoreSnapshotService.restoreFromSnapshot`) актуальный `Property` подгружается заново через `PropertyRepository`. Это даёт «свежие» картинки/цену даже если landlord что-то поменял без явной инвалидации.
4. **`dataStatus`** — строка `"COMPLETE"` или `"OVERPASS_UNAVAILABLE"`. На самом деле `OVERPASS_UNAVAILABLE` **никогда не сохраняется в БД** (см. `PropertyScoreSnapshotService.saveSnapshot`), но поле есть для будущих режимов и для отображения через REST.
5. **`algorithm_version`** — строка из `PropertyScoringService.ALGORITHM_VERSION` (на текущий момент `"v2.0"`). При деплое с обновлённой формулой:
   - В коде инкрементится `ALGORITHM_VERSION`.
   - На старте `cleanupOnStartup` удаляет все snapshot'ы с `algorithm_version != currentVersion`.
   - Дальше каждое первое открытие пересчитывает заново.

### TTL

`property.score.snapshot.ttl-hours=24`. При чтении сервис игнорирует записи старше cutoff. Cleanup устаревших записей по TTL **не реализован** (в отличие от Overpass-кэша) — пересчёт ленивый при чтении, и таблица растёт умеренно (один snapshot на пару property×profile, не больше).

### Репозиторий

[`PropertyScoreSnapshotRepository.java`](../backend/src/main/java/com/example/backend/repository/PropertyScoreSnapshotRepository.java):

```java
public interface PropertyScoreSnapshotRepository extends JpaRepository<PropertyScoreSnapshot, Long> {

    Optional<PropertyScoreSnapshot> findByPropertyIdAndProfileIdAndAlgorithmVersion(
            Long propertyId, Long profileId, String algorithmVersion);

    @Query("SELECT s FROM PropertyScoreSnapshot s WHERE s.profileId = :profileId AND s.algorithmVersion = :ver AND s.propertyId IN :propertyIds")
    List<PropertyScoreSnapshot> findAllForBatch(
            @Param("profileId") Long profileId,
            @Param("ver") String algorithmVersion,
            @Param("propertyIds") List<Long> propertyIds);

    @Modifying
    @Query("DELETE FROM PropertyScoreSnapshot s WHERE s.propertyId = :propertyId")
    int deleteByPropertyId(@Param("propertyId") Long propertyId);

    @Modifying
    @Query("DELETE FROM PropertyScoreSnapshot s WHERE s.profileId = :profileId")
    int deleteByProfileId(@Param("profileId") Long profileId);

    @Modifying
    @Query("DELETE FROM PropertyScoreSnapshot s WHERE s.algorithmVersion <> :currentVersion")
    int deleteByOldAlgorithmVersion(@Param("currentVersion") String currentVersion);
}
```

- **`findAllForBatch`** — критичная оптимизация для `scoreBatchWithSnapshot`. Один IN-запрос на N помещений вместо N отдельных.
- **`deleteByPropertyId`** — вызывается при изменении/архивации помещения.
- **`deleteByProfileId`** — при изменении критериев профиля.
- **`deleteByOldAlgorithmVersion`** — при старте приложения.

---

## 3.13. Сводная таблица всех таблиц БД

| Таблица                                | Сущность                | Назначение                                       |
|----------------------------------------|-------------------------|--------------------------------------------------|
| `users`                                | `User`                  | Учётная запись + аутентификация                  |
| `tenant_profiles`                      | `TenantProfile`         | Профиль арендатора (shared PK с users)           |
| `landlord_profiles`                    | `LandlordProfile`       | Профиль арендодателя (shared PK с users)         |
| `properties`                           | `Property`              | Объявления о помещениях                          |
| `property_images`                      | `PropertyImage`         | Фотографии помещений                             |
| `business_categories`                  | `BusinessCategory`      | Иерархия категорий + OSM-теги                    |
| `search_profiles`                      | `SearchProfile`         | Проекты поиска арендаторов                       |
| `applications`                         | `Application`           | Заявки на аренду                                 |
| `chat_rooms`                           | `ChatRoom`              | Комнаты чата (одна на заявку)                    |
| `chat_messages`                        | `ChatMessage`           | Сообщения в чате                                 |
| `property_view_events`                 | `PropertyViewEvent`     | Лог просмотров                                   |
| `favorite_events`                      | `FavoriteEvent`         | Лог добавлений в избранное                       |
| `overpass_cache`                       | `OverpassCacheEntry`    | L2-кэш OSM-снимков (TTL 7 дн)                    |
| `property_score_snapshots`             | `PropertyScoreSnapshot` | L3-кэш скоринг-оценок (TTL 24 ч)                 |
| **Join-таблицы** (без отдельной сущности):                                                                              |
| `favorites`                            | (User × Property)       | Избранные помещения арендатора                   |
| `property_existing_neighbors`          | (Property × Category)   | Существующие соседи по зданию                    |
| `search_profile_desired_neighbors`     | (SearchProfile × Category)| Желаемые соседи арендатора                     |

Итого: **14 entity-таблиц + 3 join-таблицы**.

---

## 3.14. Особенности использования JPA в проекте

1. **`FetchType.LAZY` на всех `@ManyToOne` и `@OneToOne`.** Дефолт по умолчанию для ManyToOne — EAGER; здесь явно переопределено везде. Это требует осторожности с `LazyInitializationException` за пределами Hibernate session — в `PropertyScoringService.scoreAndRankProperties` есть код принудительной инициализации перед параллельным проходом:

```java
if (profile.getBusinessCategory() != null) profile.getBusinessCategory().getName();
if (profile.getDesiredNeighbors() != null) profile.getDesiredNeighbors().size();
properties.forEach(p -> { if (p.getImages() != null) p.getImages().size(); });
```

2. **`@JsonIgnore` на чувствительных полях.** `passwordHash`, `verificationCode`, `codeExpiresAt`, lazy-associations — закрыты от случайной сериализации.

3. **`@MapsId` для shared PK.** `TenantProfile`/`LandlordProfile` используют `user_id` одновременно как PK и FK. Это эффективнее отдельного auto-increment id (один INDEX вместо двух) и логически корректно: профиль не существует без пользователя.

4. **`@CreationTimestamp` для аудита.** Используется во всех сущностях с временными метками — пишется на стороне Hibernate, не БД (PostgreSQL DEFAULT можно было бы тоже использовать, но это даёт portable-схему).

5. **`@Enumerated(EnumType.STRING)` везде.** Никаких ORDINAL — устойчиво к перестановке значений в enum'е.

6. **`columnDefinition = "TEXT"`** для длинных строк (`description`, `cover_letter`, `rejection_reason`, `content`, `response_json`, `payload_json`, `osmTags`). В PostgreSQL `TEXT` и `VARCHAR` хранятся одинаково, разница только в наличии max-length constraint.

7. **`BigDecimal` для всего, что про деньги и координаты.** Никаких `double` — детерминированность и точное хранение.
