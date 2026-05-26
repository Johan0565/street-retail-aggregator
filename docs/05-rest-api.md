# 05. REST API

Документ описывает все HTTP-эндпоинты backend'а: пути, методы, параметры, тело запроса/ответа, права доступа и коды ответов. Это «справочник по API», который надо открывать при подключении любого клиента (Flutter, Postman, Swagger).

Базовый URL: `https://api.magomedov.online` (prod) или `http://localhost:8080` (dev).
Префикс REST: **`/api`**. Все ответы — JSON. Авторизация — `Authorization: Bearer <JWT>` (см. [02-security-and-auth.md](02-security-and-auth.md)).

---

## 5.1. Сводная таблица эндпоинтов

| Контроллер              | Префикс                          | Эндпоинтов |
|-------------------------|----------------------------------|------------|
| `AuthController`        | `/api/auth`                      | 4          |
| `PropertyController`    | `/api/properties`                | 13         |
| `PropertyImageController` | `/api/properties/{id}/images`  | 3          |
| `ApplicationController` | `/api/applications`              | 6          |
| `ChatController`        | `/api/chat`                      | 4          |
| `SearchProfileController` | `/api/search-profiles`         | 6          |
| `CategoryController`    | `/api/categories`                | 6          |
| `ProfileController`     | `/api/profiles`                  | 8          |
| `AnalyticsController`   | `/api/analytics`                 | 3          |
| `InfrastructureController` | `/api/infrastructure`         | 1          |

Плюс WebSocket-endpoint `/ws` (SockJS + raw STOMP) — см. §5.10.

---

## 5.2. `/api/auth/**` — аутентификация

Все endpoints публичные (`permitAll` в `SecurityConfig`). Логика — `AuthService` (см. [02-security-and-auth.md §2.8](02-security-and-auth.md)).

### POST /api/auth/register

Регистрация. Создаёт `User` со статусом `UNVERIFIED`, генерирует 6-цифровой код, отправляет email. JWT **не выдаётся**.

**Тело:** [`RegisterRequest`](../backend/src/main/java/com/example/backend/dto/RegisterRequest.java)

```json
{
  "email": "user@example.com",
  "password": "secret123",
  "role": "TENANT",
  "name": "ИП Иванов И. И.",
  "inn": "770000000000",
  "phone": "+79991234567"
}
```

- `role` — `TENANT` или `LANDLORD`.
- Для tenant в БД создаётся `TenantProfile`, для landlord — `LandlordProfile`.
- При дубликате email/ИНН со статусом `UNVERIFIED` старая запись **удаляется** и создаётся новая (см. `AuthService.register`).
- При дубликате с `ACTIVE` — RuntimeException → 500.

**Ответ 200:** `AuthResponse { message }` без токена.

### POST /api/auth/verify

Подтверждение email-кода. При успехе — выдаёт JWT.

**Тело:**
```json
{ "email": "user@example.com", "code": "123456" }
```

- TTL кода — 2 минуты.
- При ошибке — `Неверный код` / `Код истек` / `Email уже подтвержден`.

**Ответ 200:** `AuthResponse { token, email, role, message }`.

### POST /api/auth/login

Логин. Проверяет пароль через `BCrypt`, проверяет `status=ACTIVE`, выдаёт JWT 24 часа.

**Тело:**
```json
{ "email": "user@example.com", "password": "secret123" }
```

**Ответ 200:** `AuthResponse { token, email, role, message }`.

**Ошибки:**
- Неверный пароль → 500 (RuntimeException через AuthenticationManager).
- `UserStatus.UNVERIFIED` → 500 с сообщением «Пожалуйста, подтвердите вашу электронную почту».

### POST /api/auth/resend-code?email={email}

Запрос нового кода верификации. Antiflood: разрешён, только если предыдущий код уже истёк (раз в 2 минуты).

**Ответ 200:** `AuthResponse { message }`.

---

## 5.3. `/api/properties/**` — каталог помещений

[`PropertyController.java`](../backend/src/main/java/com/example/backend/controller/PropertyController.java)

### GET /api/properties

**Публичный** (без авторизации). Возвращает все `PUBLISHED` помещения. Без скоринга.

**Ответ 200:** `Property[]`.

### GET /api/properties/{id}

**Публичный.** Карточка одного помещения по id. Включает `images[]` (полный список).

**Ответ 200:** `Property`.

**Ошибки:** 500 «Помещение не найдено».

### GET /api/properties/recommended  🔒 TENANT

Лента арендатора. Если есть активный `SearchProfile` — отсортировано по скорингу (использует L3-snapshot, может пересчитывать через Overpass). Если профилей нет — просто список PUBLISHED.

**Ответ 200:** `Property[]` (отсортирован).

### GET /api/properties/{id}/score  🔒 TENANT

Скоринг конкретного помещения под профиль арендатора.

**Query:**
- `profileId` (опц., Long) — конкретный профиль. По умолчанию — первый активный.
- `force` (опц., boolean, default `false`) — пропустить snapshot-кэш и пересчитать.

**Ответ 200:** [`ScoredPropertyDto`](../backend/src/main/java/com/example/backend/dto/ScoredPropertyDto.java) (см. структуру ниже).

**Ответ 204** — у арендатора нет ни одного активного профиля поиска.

### GET /api/properties/{id}/score-explain  🔒 TENANT

AI-объяснение скоринга на естественном русском. Идёт через OpenRouter (Llama 3.3 70B → fallback Qwen3 → GLM-4.5).

**Query:** `profileId` (опц.).

**Ответ 200:** `ScoreExplainResponse { explanation: string }`.

**Ответ 204** — нет активного профиля.

При сбое OpenRouter возвращает fallback-сообщение «AI-анализ временно недоступен».

### GET /api/properties/my  🔒 LANDLORD

Объявления текущего арендодателя, кроме `ARCHIVED`.

**Ответ 200:** `Property[]`.

### POST /api/properties  🔒 LANDLORD

Создание объявления. Статус сразу `PUBLISHED`.

**Тело:** [`CreatePropertyRequest`](../backend/src/main/java/com/example/backend/dto/CreatePropertyRequest.java) — 35+ полей, разбитых на 6 блоков:

```json
{
  "title": "Помещение в БЦ Москва",
  "description": "...",
  "address": "Москва, Тверская 5",
  "latitude": 55.7558,
  "longitude": 37.6173,
  "areaSqm": 80.0,
  "pricePerMonth": 320000.0,

  "propertyType": "RETAIL",     // OFFICE / RETAIL / WAREHOUSE / PRODUCTION / PSN / CATERING
  "dealType": "DIRECT_LEASE",   // DIRECT_LEASE / SUBLEASE
  "buildingName": "БЦ Москва",
  "buildingClass": "B_PLUS",
  "floor": 1, "totalFloors": 10, "buildYear": 2015,

  "taxIncluded": false,
  "opexIncluded": false,
  "utilityIncluded": false,
  "depositMonths": 2,
  "rentHolidays": true,
  "legalAddressProvided": true,

  "metroStation": "Тверская",
  "timeToMetro": 5,

  "powerKw": 15,
  "hasWater": true, "hasVentilation": true, "hasSeparateEntrance": true,
  "repairState": "TYPICAL",
  "ceilingHeight": 3.2,
  "layout": "OPEN_SPACE",

  "parking": "наземная, 5 мест",
  "security": "круглосуточная",
  "hasWc": true, "hasParking": true, "hasLoadingZone": false,

  "contactName": "Иван", "contactPhone": "+7...",
  "agentFee": 0,

  "cadastralNumber": "77:01:0001001:1001",
  "accessType": "FREE",
  "heatingType": "CENTRAL",
  "furnitureState": "EMPTY",
  "isOccupied": false,

  "existingNeighborCategoryIds": [12, 18]   // прим. сущ. соседи (Аптеки, Кофейни)
}
```

**Ответ 201:** созданный `Property` с присвоенным `id`.

### PUT /api/properties/{id}  🔒 LANDLORD

Обновление. Меняет только `title`, `description`, `pricePerMonth` (текущая реализация). Проверяет ownership. После save — `invalidateByProperty(id)` сбрасывает все L3-snapshot'ы этого помещения.

**Тело:** `CreatePropertyRequest`.
**Ответ 200:** обновлённый `Property`.
**500:** «Нет прав на редактирование чужого объекта».

### DELETE /api/properties/{id}  🔒 LANDLORD

Soft-delete: ставит `status=ARCHIVED`. Инвалидирует snapshot'ы.

**Ответ 204.**

### POST /api/properties/{propertyId}/favorite  🔒 TENANT

Добавление в избранное. Логирует `FavoriteEvent` (только если реально добавлено впервые).

**Ответ 200.**

### DELETE /api/properties/{propertyId}/favorite  🔒 TENANT

Удаление из избранного.

**Ответ 204.**

### GET /api/properties/favorites  🔒 TENANT

Список избранных помещений арендатора.

**Ответ 200:** `Property[]`.

---

## 5.4. `/api/properties/{id}/images/**` — фотографии

[`PropertyImageController.java`](../backend/src/main/java/com/example/backend/controller/PropertyImageController.java)

Все эндпоинты — только LANDLORD-владелец помещения. Логика — `PropertyImageService` (см. [04 §4.15](04-services-business-logic.md)). Лимит — 10 фото на помещение.

### POST /api/properties/{propertyId}/images  🔒 LANDLORD

Multipart upload. Поле — `files` (массив).

**Ограничения файлов:** JPEG / PNG / WebP, до 5MB.

**Поведение по `isMain`:**
- Если у помещения нет ни одного фото — первое загруженное становится главным.
- Иначе все новые загружаются как `isMain=false`.

**Ответ 200:** `PropertyImage[]` — список сохранённых.

### DELETE /api/properties/{propertyId}/images/{imageId}  🔒 LANDLORD

Удаление. Файл физически удаляется с ФС. Если удаляем главное — следующее первое становится главным.

**Ответ 204.**

### PUT /api/properties/{propertyId}/images/{imageId}/main  🔒 LANDLORD

Назначить главным. Атомарно: все остальные становятся `isMain=false`.

**Ответ 204.**

---

## 5.5. `/api/applications/**` — заявки

[`ApplicationController.java`](../backend/src/main/java/com/example/backend/controller/ApplicationController.java)

### POST /api/applications  🔒 TENANT

Подать заявку. Помещение должно быть `PUBLISHED`. Шлёт push арендодателю.

**Тело:** [`CreateApplicationRequest`](../backend/src/main/java/com/example/backend/dto/CreateApplicationRequest.java):
```json
{ "propertyId": 42, "coverLetter": "Хотим открыть кофейню..." }
```

**Ответ 201:** [`ApplicationResponseDto`](../backend/src/main/java/com/example/backend/dto/ApplicationResponseDto.java) с вложенными `PropertyShortInfo`, `TenantShortInfo`, `LandlordShortInfo`.

### GET /api/applications/my-requests  🔒 TENANT

Заявки текущего арендатора.

**Ответ 200:** `ApplicationResponseDto[]`.

### GET /api/applications/incoming  🔒 LANDLORD

Заявки на помещения текущего арендодателя.

**Ответ 200:** `ApplicationResponseDto[]`.

### PATCH /api/applications/{applicationId}/status  🔒 LANDLORD

Сменить статус. Проверяет ownership через `application.property.landlord`. Шлёт push tenant'у.

**Тело:** [`UpdateApplicationStatusRequest`](../backend/src/main/java/com/example/backend/dto/UpdateApplicationStatusRequest.java):
```json
{ "status": "ACCEPTED", "rejectionReason": null }
```

**Эффекты:**
- `ACCEPTED` → `Property.status = RENTED`.
- `REJECTED` → сохраняется `rejectionReason` (если передан).

**Ответ 200:** обновлённый `ApplicationResponseDto`.

### DELETE /api/applications/{applicationId}  🔒 TENANT | LANDLORD

Удаление. Доступно обеим сторонам. **Нельзя** удалить `ACCEPTED`.

**Ответ 204.**

### GET /api/applications/{applicationId}  🔒 TENANT | LANDLORD

Одна заявка. Проверка ownership по роли:
- TENANT видит только свои.
- LANDLORD — только на свои помещения.

**Ответ 200:** `ApplicationResponseDto`.

---

## 5.6. `/api/chat/**` — чат (REST-часть)

[`ChatController.java`](../backend/src/main/java/com/example/backend/controller/ChatController.java)

### GET /api/chat/applications/{applicationId}/room

Получить или создать чат-комнату по заявке. Одна заявка = одна комната.

**Ответ 200:** [`ChatRoomDto`](../backend/src/main/java/com/example/backend/dto/ChatRoomDto.java):
```json
{
  "id": 7,
  "applicationId": 42,
  "landlordId": 3, "landlordName": "owner@example.com",
  "tenantId": 5, "tenantName": "user@example.com"
}
```

### GET /api/chat/rooms

Все мои комнаты (где я landlord ИЛИ tenant).

### GET /api/chat/rooms/{roomId}/messages

Сообщения комнаты, отсортированные по `timestamp ASC`.

**Ответ 200:** [`ChatMessageDto`](../backend/src/main/java/com/example/backend/dto/ChatMessageDto.java)`[]`.

### POST /api/chat/rooms/{roomId}/messages

Послать сообщение. **Двойной канал доставки:**
1. Сохраняет в БД через `ChatService.saveMessage`.
2. **Broadcast** в `/topic/chat/{roomId}` через `SimpMessagingTemplate` — все подписчики получают real-time.
3. Шлёт push другой стороне (через `NotificationService`).

**Тело:** [`SendMessageRequest`](../backend/src/main/java/com/example/backend/dto/SendMessageRequest.java):
```json
{ "content": "Здравствуйте, помещение свободно?" }
```

**Ответ 200:** `ChatMessageDto`.

---

## 5.7. `/api/search-profiles/**` — проекты поиска арендатора

[`SearchProfileController.java`](../backend/src/main/java/com/example/backend/controller/SearchProfileController.java)

Все endpoints — только TENANT.

### POST /api/search-profiles  🔒 TENANT

Создать проект. Используется `@Valid` — поля валидируются Jakarta Validation (см. [`CreateSearchProfileRequest`](../backend/src/main/java/com/example/backend/dto/CreateSearchProfileRequest.java)).

**Тело:**
```json
{
  "name": "Открыть кофейню на Арбате",
  "businessCategoryId": 12,
  "minArea": 50, "maxArea": 80,
  "minBudget": 200000, "maxBudget": 400000,
  "minPowerKw": 10,
  "requiresWater": true, "requiresVentilation": true,
  "requiresSeparateEntrance": false, "requiresWc": true,
  "requiresParking": false, "requiresLoadingZone": false,
  "minCeilingHeight": 3.0,
  "centerLatitude": 55.7558, "centerLongitude": 37.6173,
  "searchRadiusMeters": 1000, "synergyRadiusMeters": 1500,
  "desiredNeighborCategoryIds": [18, 21]
}
```

**Валидация:**
- `name` — обязателен, до 255 символов.
- `businessCategoryId` — обязателен.
- Все числа — non-negative.

**Ответ 201:** `SearchProfile`.

### GET /api/search-profiles  🔒 TENANT

Все мои проекты.
**Ответ 200:** `SearchProfile[]`.

### GET /api/search-profiles/{id}  🔒 TENANT

Один проект (с проверкой ownership).
**Ответ 200:** `SearchProfile`.

### PUT /api/search-profiles/{id}  🔒 TENANT

Обновление. После save **инвалидирует все L3-snapshot'ы этого профиля**.
**Тело:** `CreateSearchProfileRequest`.
**Ответ 200:** обновлённый `SearchProfile`.

### DELETE /api/search-profiles/{id}  🔒 TENANT

Удаление + инвалидация snapshot'ов.
**Ответ 204.**

### ⭐ GET /api/search-profiles/{id}/scored-properties  🔒 TENANT

**Ключевой эндпоинт.** Возвращает все `PUBLISHED` помещения **со скорингом** по указанному профилю, отсортировано по убыванию `totalScore`. Использует L3-snapshot batch.

**Ответ 200:** `ScoredPropertyDto[]`.

**Может занимать 30–60с при холодном кэше** — на фронте таймаут 240с.

---

## 5.8. `/api/categories/**` — справочник категорий

[`CategoryController.java`](../backend/src/main/java/com/example/backend/controller/CategoryController.java)

Все GET — публичные (`permitAll`). POST/PUT/DELETE — только ADMIN.

### GET /api/categories

Иерархия категорий (дерево). Возвращает корневые + рекурсивно subCategories.

**Ответ 200:** [`BusinessCategoryDto`](../backend/src/main/java/com/example/backend/dto/BusinessCategoryDto.java)`[]`:
```json
[
  {
    "id": 1, "name": "Еда и напитки",
    "subCategories": [
      { "id": 12, "name": "Кофейня", "subCategories": null },
      { "id": 13, "name": "Ресторан", "subCategories": null }
    ]
  },
  ...
]
```

### GET /api/categories/flat

Плоский список без вложенности — удобнее для Dropdown.

### GET /api/categories/{id}

Одна категория с её subCategories.

### POST/PUT/DELETE /api/categories[/{id}]  🔒 ADMIN

CRUD. Тело — [`CategoryRequest`](../backend/src/main/java/com/example/backend/dto/CategoryRequest.java) `{ name, parentId }`.

---

## 5.9. `/api/profiles/**` — профили и аватары

[`ProfileController.java`](../backend/src/main/java/com/example/backend/controller/ProfileController.java)

### GET /api/profiles/tenant/me  🔒 TENANT
### GET /api/profiles/landlord/me  🔒 LANDLORD

Мой профиль. В ответ добавляется `avatarUrl` (из `User`).

**Ответ 200:** `TenantProfile` / `LandlordProfile`.

### PUT /api/profiles/tenant/me  🔒 TENANT

**Тело:** [`UpdateTenantProfileRequest`](../backend/src/main/java/com/example/backend/dto/UpdateTenantProfileRequest.java):
```json
{ "name": "Иван", "inn": "...", "phone": "+7...", "targetBusinessCategoryId": 12 }
```

### PUT /api/profiles/landlord/me  🔒 LANDLORD

**Тело:** [`UpdateLandlordProfileRequest`](../backend/src/main/java/com/example/backend/dto/UpdateLandlordProfileRequest.java):
```json
{ "companyName": "ООО Ромашка", "inn": "...", "phone": "+7..." }
```

### POST /api/profiles/me/avatar

Multipart upload (поле `file`). Валидация — JPEG/PNG/WebP до 5MB. Старый аватар удаляется с ФС.

**Ответ 200:** `{ "avatarUrl": "/uploads/avatars/5/uuid.jpg" }`.

### DELETE /api/profiles/me/avatar

Удалить аватар. **Ответ 204.**

### GET /api/profiles/tenant/{userId}
### GET /api/profiles/landlord/{userId}

Публичный просмотр профиля. Используется в карточке заявки для отображения контактов другой стороны.

---

## 5.10. `/api/analytics/**` — аналитика и события

[`AnalyticsController.java`](../backend/src/main/java/com/example/backend/controller/AnalyticsController.java)

### GET /api/analytics/my-properties  🔒 LANDLORD

Сводная аналитика по всем неархивным помещениям владельца за 30 дней.

**Ответ 200:** [`AnalyticsDto`](../backend/src/main/java/com/example/backend/dto/AnalyticsDto.java):
```json
{
  "totalViewsLast30Days": 142,
  "totalFavoritesLast30Days": 18,
  "totalApplications": 25,
  "totalApplicationsLast30Days": 7,
  "totalUniqueMessengers": 5,
  "viewsByDate": {"2026-05-01": 5, "2026-05-02": 8, ...},
  "favoritesByDate": {...},
  "applicationsByDate": {...},
  "propertyId": null, "propertyTitle": null
}
```

Просмотры **дедуплицируются** по паре `(property, viewer)` — повторное открытие одной карточки одним пользователем считается одним просмотром.

### GET /api/analytics/property/{propertyId}  🔒 LANDLORD

Аналитика по одному помещению. Доп. проверка ownership: если не владелец — 403.

### POST /api/analytics/view/{propertyId}

**Публично-приемлемый** (но Spring требует auth для всего, кроме явных permitAll-путей — этот не в списке, поэтому всё-таки нужен токен). Логирует `PropertyViewEvent`. Если `principal == null` — `viewer=null` (анонимный просмотр).

**Ответ 200.**

---

## 5.11. `/api/infrastructure` — POI вокруг точки

[`InfrastructureController.java`](../backend/src/main/java/com/example/backend/controller/InfrastructureController.java)

### GET /api/infrastructure?lat={lat}&lon={lon}&radius={radius}

Список POI вокруг точки (метро, кафе, университеты). Идёт через `InfrastructureService` напрямую к публичному overpass-api.de (без локального кэша). Без скоринга.

**Параметры:** `lat`, `lon` (double, обязательно), `radius` (int, default `500`).

**Ответ 200:** `PoiDto[]`:
```json
[
  { "name": "Тверская", "category": "metro", "distanceMeters": 220 },
  { "name": "Кофемания", "category": "cafe", "distanceMeters": 340 }
]
```

**Замечание:** legacy-сервис, требует рефакторинга (см. [04 §4.18](04-services-business-logic.md)).

---

## 5.12. WebSocket / STOMP — реал-тайм чат

Endpoint **`/ws`** (без префикса `/api`). Регистрируется в [`WebSocketConfig`](../backend/src/main/java/com/example/backend/config/WebSocketConfig.java). Два варианта: SockJS-fallback и raw WebSocket. Открытый CORS (`setAllowedOriginPatterns("*")`).

### Подключение

```
ws://localhost:8080/ws        (raw STOMP)
http://localhost:8080/ws       (SockJS fallback для браузеров)
```

С `Authorization: Bearer <JWT>` заголовком (STOMP CONNECT frame).

### Subscribe

```
SUBSCRIBE /topic/chat/{roomId}
```

Подписка на сообщения конкретной комнаты. Сервер шлёт сюда `ChatMessageDto` (JSON) при вызове POST `/api/chat/rooms/{roomId}/messages`.

### Publish

В текущей реализации **publish с клиента не используется** — сообщения шлются через REST (POST), а WebSocket нужен только для **получения** real-time обновлений. Это упрощает auth: REST уже валидирует JWT, не нужно дублировать в STOMP.

Конфиг включает `/app` префикс для будущих `@MessageMapping`-эндпоинтов, но они не зарегистрированы.

---

## 5.13. Структура `ScoredPropertyDto`

Самый сложный DTO в API. Полный пример:

```json
{
  "property": { /* объект Property с images */ },

  "totalScore": 72,
  "financialScore": 18,
  "technicalScore": 15,
  "competitorScore": 28,
  "synergyScore": 8,
  "transportScore": 3,

  "directCompetitorNames": ["Аптека 36,6", "Ригла", "Самсон-фарма"],
  "synergyNeighborNames": ["БЦ Москва", "МГУ им. Ломоносова"],

  "matchLabel": "👍 Хороший вариант",
  "matchColor": "yellow",

  "dataStatus": "COMPLETE",
  "computedAt": "2026-05-25T13:42:11",
  "algorithmVersion": "v2.0",

  "breakdown": {
    "financial": {
      "budgetPoints": 9.0, "budgetReason": "цена в бюджете",
      "areaPoints": 9.0, "areaReason": "площадь в диапазоне"
    },
    "technical": {
      "items": [
        { "requirement": "парковка", "penalty": 1.0, "reason": "не указано (половина штрафа)" }
      ]
    },
    "competitor": {
      "weightedDirect": 0.83,
      "directRefs": [
        {
          "name": "Аптека 36,6",
          "distanceMeters": 150, "weight": 0.64,
          "latitude": 55.756, "longitude": 37.618,
          "scoreImpact": -7.2
        }
      ],
      "totalNearbyBusinesses": 42, "radiusMeters": 1000
    },
    "synergy": {
      "desiredCategoriesCount": 2, "foundCategoriesCount": 1,
      "refs": [
        {
          "name": "МГУ",
          "distanceMeters": 800, "weight": 0.09,
          "latitude": 55.703, "longitude": 37.530,
          "scoreImpact": 3.2
        }
      ]
    },
    "transport": {
      "nearestName": "Арбатская", "nearestType": "METRO",
      "nearestDistanceMeters": 220,
      "reason": "метро «Арбатская» в 220 м (бонус 3/5)"
    }
  }
}
```

**Значения `dataStatus`:**
- `COMPLETE` — все компоненты посчитаны.
- `OVERPASS_UNAVAILABLE` — Overpass упал; `totalScore` = только `financial+technical`; competitor/synergy/transport = 0. Фронт показывает «⚠️ Частичная оценка».

**Значения `matchColor`:** `green` (≥75), `yellow` (≥50), `red` (<50), `gray` (OVERPASS_UNAVAILABLE).

---

## 5.14. Ответы и коды ошибок

### Стандартные коды

| Код | Значение в API                                                   |
|-----|------------------------------------------------------------------|
| 200 | OK                                                               |
| 201 | Created (после POST creates)                                     |
| 204 | No Content (после DELETE и для «нет данных для скоринга»)        |
| 403 | Forbidden — нет JWT, неверная роль, чужой ресурс                 |
| 500 | Internal Server Error — текущий backend бросает `RuntimeException` без явных ResponseStatus, поэтому большинство бизнес-ошибок («Помещение не найдено», «Нет прав на редактирование чужого объекта») возвращаются именно 500. |

### Замечания

- **JWT istanbul** возвращает 403 (не 401) — особенность Spring Security 6 default'а.
- **`@PreAuthorize`** при неподходящей роли — 403.
- **Validation errors** (`@Valid` на `CreateSearchProfileRequest`) → 400 с автогенерированным телом.
- Ownership-проверки внутри сервисов бросают `RuntimeException` → 500. Желательно мигрировать на `@ResponseStatus` exception'ы для корректных 403/404.

---

## 5.15. Аутентификация в API

| Группа путей                                          | Auth          |
|-------------------------------------------------------|---------------|
| `/api/auth/**`                                        | публичный     |
| `/api/properties/{id}` (GET)                          | публичный     |
| `/api/properties` (GET всех)                          | публичный     |
| `/api/categories/**` (GET)                            | публичный     |
| `/uploads/**`                                         | публичный     |
| `/v3/api-docs/**`, `/swagger-ui/**`                   | публичный     |
| `/ws/**`                                              | публичный (auth на уровне STOMP) |
| Все остальные                                         | требуется JWT |

### Заголовок

```
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9...
```

JWT живёт 24 часа. Извлечение `userId` из `Principal` — через `UsernamePasswordAuthenticationToken.getPrincipal()` → `User.id`.

---

## 5.16. Swagger UI

Документация автогенерируется springdoc-openapi:
- **Swagger UI:** `http://localhost:8080/swagger-ui.html`
- **OpenAPI 3 JSON:** `http://localhost:8080/v3/api-docs`

В Swagger UI есть кнопка `Authorize` — после ввода Bearer-токена все запросы автоматически авторизованы (см. [`SwaggerConfig`](../backend/src/main/java/com/example/backend/auth/SwaggerConfig.java)).

---

## 5.17. Cheat-sheet «фича → endpoint»

| Фича                              | HTTP / WS                                                          |
|-----------------------------------|---------------------------------------------------------------------|
| Регистрация                       | `POST /api/auth/register` → `POST /api/auth/verify`                |
| Логин                             | `POST /api/auth/login`                                             |
| Лента арендатора со скорингом     | `GET /api/properties/recommended` + `GET /api/search-profiles/{id}/scored-properties` |
| Карточка помещения                | `GET /api/properties/{id}`                                         |
| Скоринг одной карточки            | `GET /api/properties/{id}/score?profileId=...`                     |
| AI-объяснение                     | `GET /api/properties/{id}/score-explain`                           |
| Избранное                         | `POST/DELETE /api/properties/{id}/favorite`, `GET /api/properties/favorites` |
| Создать объявление                | `POST /api/properties` + `POST /api/properties/{id}/images`        |
| Управлять фото                    | `DELETE`, `PUT .../main` в `/api/properties/{id}/images`           |
| Заявки tenant                     | `POST /api/applications`, `GET /api/applications/my-requests`      |
| Заявки landlord                   | `GET /api/applications/incoming`, `PATCH .../status`               |
| Чат                               | REST: `/api/chat/**`; WS: `SUBSCRIBE /topic/chat/{roomId}`         |
| Аналитика landlord                | `GET /api/analytics/my-properties`, `GET /api/analytics/property/{id}` |
| Профиль                           | `GET/PUT /api/profiles/{tenant\|landlord}/me`                       |
| Аватар                            | `POST/DELETE /api/profiles/me/avatar`                              |
| Категории                         | `GET /api/categories`, `GET /api/categories/flat`                  |
| Управление проектами поиска       | `POST/GET/PUT/DELETE /api/search-profiles`                         |
| POI вокруг точки                  | `GET /api/infrastructure?lat=&lon=&radius=`                        |
