# 06. Frontend — экраны (UI)

Документ описывает все экраны Flutter-приложения: иерархию навигации, отдельные экраны, ключевые UI-элементы и взаимодействие со слоем сервисов.

---

## 6.1. Карта экранов

```
                 main.dart
                     │
                     ▼
              SplashScreen
                     │ checkAutoLogin() + resumeSavedAccount()
                     ▼
        ┌────────────┼────────────┐
        ▼            ▼            ▼
    LoginScreen  TenantMain    LandlordMain
        │           Screen        Screen
        ▼            │              │
    RegisterScreen   │              │
                     ▼              ▼
        ┌──────┬──────┬──────┬──────┐    ┌──────┬──────┬──────┬──────┐
        │      │      │      │      │    │      │      │      │      │
        ▼      ▼      ▼      ▼      ▼    ▼      ▼      ▼      ▼      ▼
       Map  Favorites My  Search Profile Map  My   (FAB) Incoming Profile
            Screen   Apps Profile Screen  Screen Props +Add  Apps
                          Screens               Screen Property
                                                       Screen
                                                  ↓ tap карточки
                                                  AnalyticsScreen
                                                  (per-property)
                                                  
                          ↓ tap карточки
                  PropertyDetailsScreen
                          │
                          ▼
                       ChatScreen (по applicationId)
```

**Главная техника навигации:** `IndexedStack` в `TenantMainScreen` / `LandlordMainScreen`. Все вкладки одновременно живут в памяти, переключение между ними сохраняет состояние (скролл, ввод). Перезагрузка данных при возврате на вкладку — через `GlobalKey<State>` + публичный `loadXxx()` метод.

---

## 6.2. Цветовая схема и стек UI-зависимостей

**Основной акцент:** `#FFF8C00` (оранжевый) — фирменный цвет приложения.

```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8C00)),
  useMaterial3: true,
)
```

**UI-стек:**

| Пакет                    | Назначение                                         |
|--------------------------|----------------------------------------------------|
| `yandex_mapkit ^4.2.1`   | Карта (тайлы Яндекс), search by point, suggest    |
| `fl_chart ^1.2.0`        | Графики в аналитике                                |
| `pinput ^6.0.2`          | Ввод 6-цифрового кода верификации                  |
| `cached_network_image`   | Кэширование картинок                               |
| `image_picker`           | Выбор фото из галереи/камеры                       |
| `flutter_image_compress` | Сжатие картинок перед upload (~1600px, q=80)       |
| `flutter_secure_storage` | Хранение JWT, мульти-аккаунтов                     |
| `stomp_dart_client`      | STOMP-клиент для чата                              |
| `jwt_decoder`            | Парсинг JWT (expiry, claims)                       |
| `dio`                    | HTTP-клиент для REST                               |
| `geolocator` / `geocoding` | Геолокация (для map picker)                      |

---

## 6.3. Точка входа: `main.dart` и `SplashScreen`

[`main.dart`](../frontend/lib/main.dart)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();
  NotificationService().handleIncomingMessages();
  runApp(const MyApp());
}
```

- Инициализация `NotificationService` (заглушка под FCM, см. [07 §7.x](07-frontend-services-and-domain.md)).
- Корень — `MyApp` → `MaterialApp` с `home: SplashScreen()`.

### SplashScreen

```dart
Future<void> _checkAuth() async {
  await Future.delayed(const Duration(milliseconds: 500));

  final auth = AuthService();
  String? role = await auth.checkAutoLogin();

  if (role == null) {
    final accounts = await auth.getSavedAccounts();
    for (final acc in accounts) {
      final resumed = await auth.resumeSavedAccount(acc.email);
      if (resumed != null) {
        role = resumed;
        break;
      }
    }
  }

  if (role == 'TENANT')   → TenantMainScreen
  else if (role == 'LANDLORD') → LandlordMainScreen
  else → LoginScreen
}
```

**Логика автологина:**
1. Проверить `remember_me==true` + текущий токен ещё не истёк → пускаем сразу.
2. Если основной токен пустой/истёк — пробежаться по `savedAccounts`, найти первый с живым JWT и возобновить сессию (мульти-аккаунт fallback).
3. Иначе → `LoginScreen`.

UI на этом этапе — белый фон с оранжевым `CircularProgressIndicator(color: 0xFFFF8C00)`.

---

## 6.4. Аутентификация

### LoginScreen

[`login_screen.dart`](../frontend/lib/src/presentation/screens/auth/login_screen.dart)

**UI-элементы:**
- Анимированный логотип (`AnimationController` 900мс, `Curves.easeOutBack` для scale + fade).
- Поля Email и Password (с toggle видимости).
- Checkbox «Запомнить меня».
- Кнопка «Войти» (оранжевая).
- Кнопка «Зарегистрироваться» → `RegisterScreen`.
- **Список сохранённых аккаунтов** (если есть) — chip'ы с инициалами для быстрого переключения. Чип берёт `displayName` или email, рисует avatar с инициалами.

**Логика:**
- `_loadSavedData` подгружает `savedAccounts` и автозаполняет `email`/`remember_me`.
- При нажатии на сохранённый аккаунт-чип — вызывает `resumeSavedAccount(email)`, моментально переходит в соответствующий main.

**Анимации:**
- Логотип: scale 0.75 → 1.0 с easeOutBack.
- Контент: slide снизу + fade.

### RegisterScreen

[`register_screen.dart`](../frontend/lib/src/presentation/screens/auth/register_screen.dart)

**Поля:**
- Email, Password (с обскур toggle).
- Имя / Название компании.
- ИНН (текст, без маски).
- Телефон.
- **Выбор роли** — кастомные карточки TENANT/LANDLORD (с иконками `assets/tenant.png`, `assets/landlord.png`).

**Логика:**
1. `auth.register(...)` → POST `/api/auth/register`.
2. Если успех — переход на экран ввода кода (внутри того же RegisterScreen, через `PageView` или модальный sheet с `pinput`).
3. `pinput` 6-цифровой ввод → `auth.verifyEmail(...)` → если OK, в `_activateSession` сохраняется token+role → пробрасывает на main.

---

## 6.5. Tenant — главная навигация

[`tenant_main_screen.dart`](../frontend/lib/src/presentation/screens/tenant/tenant_main_screen.dart)

**Структура:** `IndexedStack` с 5 экранами. Bottom navigation — плавающая чёрная пилюля (`Container` с `borderRadius: 32`) с анимированным фоном выделенной вкладки.

```dart
late final List<Widget> _screens = [
  MapScreen(key: _mapKey),              // 0 — Карта
  FavoritesScreen(key: _favoritesKey),  // 1 — Избранное
  MyApplicationsScreen(key: _applicationsKey), // 2 — Заявки
  const SearchProfilesScreen(),         // 3 — Проекты
  const ProfileScreen(),                // 4 — Профиль
];
```

**Особенности:**

1. **GlobalKey + публичный `loadXxx()`.** При переключении на вкладку 1, 2 или 0 — принудительный rebuild:
```dart
if (index == 1) _favoritesKey.currentState?.loadFavorites();
if (index == 2) _applicationsKey.currentState?.loadApplications();
if (index == 0) _mapKey.currentState?.reloadProfiles();
```
Это компенсирует то, что `IndexedStack` не «оживляет» дочерние состояния при возврате.

2. **Стилизация nav-item:** при выделении `AnimatedContainer` (duration 300мс) расширяется и показывает текст-лейбл рядом с иконкой:

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOut,
  decoration: BoxDecoration(
    color: isSelected ? _primaryOrange.withOpacity(0.2) : Colors.transparent,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Row(children: [
    Icon(isSelected ? activeIcon : icon, color: ...),
    if (isSelected) ...[const SizedBox(width: 6), Text(label, ...)]
  ]),
)
```

3. `extendBody: true` — карта рисуется **под** плавающей панелью.

---

## 6.6. Tenant — `MapScreen` (карта)

[`map_screen.dart`](../frontend/lib/src/presentation/screens/tenant/map_screen.dart)

Главный экран арендатора. Карта Yandex MapKit с маркерами помещений, цвет которых отражает скоринг (если выбран активный профиль поиска).

### Ключевые поля состояния

```dart
List<MapObject> mapObjects = [];

// Скоринг
List<SearchProfile> _myProfiles = [];
SearchProfile? _activeProfile;
Map<int, ScoredProperty> _scoreCache = {};
List<Property> _allProperties = [];
PropertyFilter _activeFilter = PropertyFilter.empty;

// Локально просмотренные (для серовато-оранжевой метки)
Set<int> _viewedPropertyIds = <int>{};

// Поиск адреса (Yandex SuggestSession)
final TextEditingController _searchController = TextEditingController();
Timer? _searchDebounce;
List<SuggestItem> _searchSuggestions = [];
```

### UI-элементы

1. **Карта** (`YandexMap` с кастомным JSON-стилем — притушённая палитра под оранжевый акцент).
2. **Search bar сверху** — Yandex Suggest с debounce 300мс. При тапе на suggestion — `moveCamera(point, zoom: 16)`.
3. **Маркеры помещений** — кастомные `PlacemarkMapObject` с биткарой, нарисованной через `ui.PictureRecorder`:
   - Без скоринга — серый круг с ценой.
   - Со скорингом — оранжевый/жёлтый/красный круг + emoji `🔥/👍/⚠️/❌` + балл.
   - Просмотренные — затемнены.
4. **Dropdown «Проект поиска»** — выбор `_activeProfile` из `_myProfiles`. При смене — пересчитывает scoring через `searchProfileService.getScoredProperties(profileId)` (длинный запрос, до 240с).
5. **Bottom sheet с карточкой** при тапе на маркер — `showModalBottomSheet` с превью, ценой, баллом, кнопкой «Подробнее» → `PropertyDetailsScreen`.
6. **FAB фильтров** — открывает sheet с `PropertyFilter` (см. [07 §7.4](07-frontend-services-and-domain.md)).
7. **Маркер фокуса** (`_focusMarker`) — оранжевая точка, ставится после возврата с `PropertyDetailsScreen` если пользователь тапнул конкретного соседа-конкурента в шторке. Стирается при первом тапе по карте.

### Landlord mode

```dart
const MapScreen({super.key, this.isLandlordMode = false});
```

В режиме `isLandlordMode=true` (используется в `LandlordMainScreen`):
- Скоринг не показывается.
- Маркеры просто показывают свои объявления.
- Тап → детали с edit-controls.

---

## 6.7. Tenant — `PropertyDetailsScreen`

[`property_details_screen.dart`](../frontend/lib/src/presentation/screens/tenant/property_details_screen.dart)

Карточка одного помещения. Сразу при открытии:
- Логирует просмотр: `AnalyticsService().logPropertyView(property.id)` → POST `/api/analytics/view/{id}` + локальный `ViewedPropertiesStore`.
- Проверяет статус «в избранном».
- Догружает полный объект через `getPropertyById(id)` — потому что список `/api/properties` может вернуть объект без `images` из-за обрезки.

### UI-структура

```
┌─────────────────────────────────────┐
│ ◄ [Назад]              [♥ Избранное]│  AppBar
├─────────────────────────────────────┤
│                                     │
│   PageView с фотографиями           │
│   (PhotoController, dots indicator) │
│                                     │
├─────────────────────────────────────┤
│ Заголовок                  220 000₽ │
│ Адрес, м. Тверская                  │
│                                     │
│ [80м²] [RETAIL] [3-этаж] [B+]       │  chip'ы
│                                     │
│ ┌─ Скоринг 75/100 ─────────────────┐│
│ │ [🔥 Отличный мэтч!]              ││
│ │ Финансы 18/20 ▒▒▒▒▒▒▒▒▒░         ││  прогрессбары
│ │ Техника 15/20  ▒▒▒▒▒▒▒░░         ││
│ │ Конкуренты 28/40  ▒▒▒▒▒░         ││
│ │ Синергия 9/15  ▒▒▒▒░░░░          ││
│ │ Транспорт 5/5  ▒▒▒▒▒▒▒▒▒▒        ││
│ │ [Подробнее]  [AI-объяснение]     ││
│ └──────────────────────────────────┘│
│                                     │
│ Описание...                         │
│ [Технические характеристики]        │  expansion tiles
│ [Финансовые условия]                │
│ [Контакты]                          │
│                                     │
│ [   Подать заявку (FAB)   ]         │
└─────────────────────────────────────┘
```

### Шторки «Конкуренты» и «Синергия»

При тапе на любую часть breakdown — открывается `showModalBottomSheet` с детальной разбивкой:

**Конкуренты:**
- Список `CompetitorRef` отсортирован по близости.
- Для каждого: имя, расстояние, weight, `scoreImpact` (на сколько баллов «съел»).
- Тап на конкурента → возврат `PropertyDetailsFocusResult { latitude, longitude }` в `MapScreen` → камера летит к этой точке.

**Синергия:**
- `SynergyRef` с такими же атрибутами + `scoreImpact > 0`.
- Если `desiredNeighborNames` непустой, но рядом никого не нашлось — показывается список «не найдено» с серыми чипами.

### Кнопка «AI-объяснение»

Открывает `BottomSheet` с lottie-индикатором, ждёт ответ (45с timeout). Получает текст в 6 структурированных блоков от LLM (см. [04 §4.8](04-services-business-logic.md)). При сбое — fallback-сообщение.

### Кнопка «Подать заявку»

Открывает диалог с `TextField` для `coverLetter` (опционально). Send → `ApplicationService.createApplication(propertyId, coverLetter)` → SnackBar успех/ошибка.

### Landlord mode

В `isLandlordMode=true`:
- «Избранное» не показывается.
- Появляются кнопки «Редактировать» (→ `AddPropertyScreen` с предзаполнением) и «Архивировать» (`DELETE /api/properties/{id}`).
- Кнопка «Аналитика» → `AnalyticsScreen(propertyId: id)`.

---

## 6.8. Tenant — `FavoritesScreen`

[`favorites_screen.dart`](../frontend/lib/src/presentation/screens/tenant/favorites_screen.dart)

Простой список избранного.

**UI:**
- `AppBar` «Избранное».
- `FutureBuilder<List<Property>>` → `ListView` с карточками `Property`.
- Пустое состояние: иконка ♥ + текст «Пока пусто».

**Метод обновления:**
```dart
Future<void> loadFavorites() async {
  final future = _favoriteService.getMyFavorites();
  setState(() { _favoritesFuture = future; });
  await future;
}
```

Вызывается из `TenantMainScreen` при переходе на вкладку.

---

## 6.9. Tenant — `MyApplicationsScreen`

[`my_applications_screen.dart`](../frontend/lib/src/presentation/screens/tenant/my_applications_screen.dart)

Мои заявки с фильтрами и сортировкой.

**UI:**
- Список карточек заявок с статусом-бейджем (цвет по `_getStatusInfo`).
- Filter bar: статус (`ALL/PENDING/REVIEWING/ACCEPTED/REJECTED`), сортировка (новые/старые), checkbox «Только с письмом».
- При тапе на заявку → расширенная карточка с:
  - Адресом помещения.
  - Текстом сопроводительного письма.
  - `rejectionReason` (если REJECTED) — красный блок.
  - Контактами landlord'a.
  - Кнопкой «Открыть чат» → `ChatScreen(applicationId, title)`.
  - Кнопкой «Отозвать заявку» (если status != ACCEPTED).

**Логика статусов (RU перевод):**
```dart
'PENDING'    → ('На рассмотрении', Colors.grey[600])
'REVIEWING'  → ('Изучается', Colors.blue)
'ACCEPTED'   → ('Одобрено', Colors.green)
'REJECTED'   → ('Отклонено', Colors.red)
```

---

## 6.10. Tenant — `SearchProfilesScreen`

[`search_profiles_screen.dart`](../frontend/lib/src/presentation/screens/tenant/search_profiles_screen.dart)

CRUD проектов поиска.

**UI:**
- Список проектов: карточки с названием, активностью (бейдж), категорией бизнеса.
- FAB «+» → wizard создания (полная форма со всеми полями `SearchProfile`).
- Swipe-to-delete или меню кнопка → `_deleteProfile` с подтверждением:
```dart
showDialog → AlertDialog → confirm → service.deleteProfile(id)
```
- Тап на проект → редактор.

**Особенность:** удаление проекта на бэкенде вызывает `invalidateByProfile(profileId)` — все L3-snapshot'ы под этот профиль чистятся.

---

## 6.11. Tenant — `ProfileScreen` (универсальный)

[`profile_screen.dart`](../frontend/lib/src/presentation/screens/tenant/profile_screen.dart)

Используется и tenant, и landlord (определяется по `user_role` из storage).

**UI-элементы:**
- Аватар (`CachedNetworkImage` через `ImageHelper.toAbsoluteUrl`) + кнопка изменить (→ `pickImages` → `auth.uploadAvatar`).
- Имя / Название компании (редактируемое).
- ИНН (readonly).
- Телефон (редактируемый).
- Для TENANT — Dropdown «Целевая категория бизнеса» (`targetBusinessCategoryId`).
- Switch «Уведомления» (UI-only, в текущей реализации не привязан).
- Кнопка «Сохранить» → `auth.updateProfile(name, phone, categoryId)`.
- Кнопка «Сменить пароль» (не реализовано).
- Кнопка «Выйти» → `auth.logout()` → `LoginScreen`.

**Особенности:**
- При успешном обновлении профиля имя обновляется в `savedAccount.displayName` (через `_refreshActiveAccountName`).
- Аватар хранится как относительный URL (`/uploads/avatars/{userId}/uuid.jpg`), фронт префиксует через `ImageHelper.toAbsoluteUrl`.

---

## 6.12. Landlord — главная навигация

[`LandlordMainScreen.dart`](../frontend/lib/src/presentation/screens/landlord/LandlordMainScreen.dart)

4 вкладки + центральный FAB «+» для добавления.

```dart
late final List<Widget> _screens = [
  const MapScreen(isLandlordMode: true), // 0 — Карта
  MyPropertiesScreen(key: _myPropertiesKey), // 1 — Объекты
  const IncomingApplicationsScreen(),    // 2 — Заявки
  const ProfileScreen(),                 // 3 — Профиль
];
```

**FAB** (`FloatingActionButton.centerDocked`) → `AddPropertyScreen` через `MaterialPageRoute(fullscreenDialog: true)`. После возврата с `true` — `_myPropertiesKey.currentState?.loadProperties()`.

---

## 6.13. Landlord — `MyPropertiesScreen`

[`my_properties_screen.dart`](../frontend/lib/src/presentation/screens/landlord/my_properties_screen.dart)

Мои объявления с фильтрами.

**UI:**
- Search bar (текстовый поиск по title).
- Chip-фильтры: статус (`ALL/PUBLISHED/ARCHIVED`), тип помещения (`OFFICE/RETAIL/WAREHOUSE/PSN/CATERING`).
- Карточки с превью, ценой, статус-бейджем, action-меню.
- Тап → `PropertyDetailsScreen(isLandlordMode: true)`.

**Лейблы типов** (`_typeLabels` const map):
```dart
'OFFICE'    → 'Офис'
'RETAIL'    → 'Стрит-ритейл'
'WAREHOUSE' → 'Склад'
'PSN'       → 'ПСН'
'CATERING'  → 'Общепит'
```

**Action-меню:**
- Редактировать → `AddPropertyScreen` (предзаполнение).
- Аналитика → `AnalyticsScreen(propertyId, propertyTitle)`.
- Архивировать → `_propertyService.deleteProperty(id)` (soft-delete).

---

## 6.14. Landlord — `AddPropertyScreen`

[`add_property_screen.dart`](../frontend/lib/src/presentation/screens/landlord/add_property_screen.dart)

5-шаговый wizard добавления помещения.

**Шаги:**
1. **Базовая** — title, address (+ MapPicker), area, propertyType, dealType, layout.
2. **Финансы** — price, tax/utility included, depositMonths.
3. **Технические** — powerKw, ceilingHeight, repair, has* (water, ventilation, separate entrance, wc, parking, loading), access/heating/furniture state, cadastralNumber.
4. **Контакты** — contactName, contactPhone.
5. **Фото** — `_photos: List<File>` через `ImageHelper.pickImages(allowMultiple: true)`, превью с возможностью выбора главного, удаление.

**Каждый шаг — свой `Form` с `GlobalKey<FormState>`** (массив `_formKeys[5]`). При переходе «Далее» — `_formKeys[i].currentState!.validate()`.

**Submit:**
1. `propertyService.createProperty(...)` → id.
2. Если фото есть → `propertyService.uploadPropertyImages(id, _photos)` (multipart, до 60с timeout).
3. Если `_mainPhotoIndex != 0` — `setMainPropertyImage(id, returnedImages[index].id)`.
4. `Navigator.pop(context, true)` → MyPropertiesScreen перезагружается.

---

## 6.15. Landlord — `MapPickerScreen`

[`map_picker_screen.dart`](../frontend/lib/src/presentation/screens/landlord/map_picker_screen.dart)

Модал для выбора точки на карте при создании объявления.

**UI:**
- `YandexMap` с центральной меткой-индикатором.
- Search bar сверху (`YandexSuggest` с debounce 500мс).
- При остановке камеры — `YandexSearch.searchByPoint(point, zoom: 17)` для **обратного геокодирования** → отображает текущий адрес снизу.
- FAB «Геолокация» — `Geolocator.getCurrentPosition()` → центр карты.
- Кнопка «Выбрать» снизу → возврат `(latitude, longitude, address)` в `AddPropertyScreen`.

**Debounce'ы:**
- Suggest: 500мс задержка после изменения текста.
- Reverse-geocode: 600мс после остановки камеры.

---

## 6.16. Landlord — `IncomingApplicationsScreen`

[`incoming_applications_screen.dart`](../frontend/lib/src/presentation/screens/landlord/incoming_applications_screen.dart)

Входящие заявки с фильтрами/сортировкой (структура аналогична `MyApplicationsScreen` арендатора, но с другими действиями).

**UI:**
- Те же фильтры (`ALL/PENDING/ACCEPTED/REJECTED`, sort, onlyWithLetter).
- Карточка заявки с контактами арендатора, сопроводительным письмом, кнопками:
  - **Принять** → `_applicationService.updateApplicationStatus(id, 'ACCEPTED')` → Property переходит в RENTED, push tenant'у.
  - **Отклонить** → диалог с обязательным `rejectionReason` → `updateApplicationStatus(id, 'REJECTED', rejectionReason: text)`.
  - **Открыть чат** → `ChatScreen(applicationId, ...)`.

---

## 6.17. Landlord — `AnalyticsScreen`

[`analytics_screen.dart`](../frontend/lib/src/presentation/screens/landlord/analytics_screen.dart)

Графики и сводка событий. Двухрежимный:
```dart
const AnalyticsScreen({super.key, this.propertyId, this.propertyTitle});
// propertyId == null → общая (getMyAnalytics)
// propertyId != null → per-property (getPropertyAnalytics)
```

**UI:**
- AppBar с заголовком (общая / по конкретному помещению).
- 4 карточки-метрики:
  - Просмотров за 30 дн.
  - В избранное.
  - Заявок (всего / за 30 дн).
  - Уникальных «собеседников» (только для общей).
- 3 графика (`fl_chart`):
  - **Views by date** — bar chart по дням за 30 дней.
  - **Favorites by date** — line chart.
  - **Applications by date** — bar chart.
- Цвета: оранжевый `#FFF8C00`, фиолетовый `#7C3AED`, бирюзовый `#14B8A6`.
- `RefreshIndicator` — pull-to-refresh.

---

## 6.18. Чат — `ChatScreen`

[`chat_screen.dart`](../frontend/lib/src/presentation/screens/chat/chat_screen.dart)

Общий экран для tenant и landlord, открывается по `applicationId`.

**Поток инициализации:**
```dart
1. await _chatService.getOrCreateRoom(applicationId) → ChatRoom
2. await _chatService.getMessages(room.id) → List<ChatMessage>
3. _chatService.connectStomp(room.id, onMessage) — WebSocket subscribe
```

**UI:**
- AppBar с названием заявки.
- `ListView.builder` с сообщениями.
- Сообщения — облачка двух цветов: оранжевый (мои) справа, серый (другие) слева.
- Внизу: `TextField` + кнопка «отправить».

**Отправка:**
```dart
await _chatService.sendMessage(room.id, content);
// REST POST → BD save + WS broadcast → onMessage callback в WS-subscribe
```

WS-callback дедуплицирует по `message.id` (если REST вернул сообщение, оно уже в списке — WS его не дублирует).

**Текущий userId** — извлекается из JWT через `JwtDecoder.decode(token)` (поля `userId` или `id`). В текущей реализации это не идеально: backend JWT кладёт только `sub` (email), поэтому работает скорее по совпадению.

**Disconnect:** в `dispose()` — `_chatService.disconnectStomp()`.

---

## 6.19. Общие UI-паттерны

### Цвета статусов
- **Оранжевый primary** `#FFF8C00` — везде.
- **Зелёный** `#22C55E` — успешные действия, высокий скор.
- **Жёлтый** `#F59E0B` — средний скор, warning.
- **Красный** `#EF4444` — отказ, низкий скор, удаление.
- **Серый** `#94A3B8` — disabled, OVERPASS_UNAVAILABLE.

### Loading
- `CircularProgressIndicator(color: 0xFFFF8C00)` — везде одинаково.
- В долгих операциях (скоринг батча) — TextOverlay «Считаем баллы под ваш проект...».

### Form validation
- `TextFormField` с `validator: (v) => v == null || v.isEmpty ? 'Заполните' : null`.
- Числа: `TextInputType.number` + custom validator на range/format.

### Snackbars
- Успех: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('...'), backgroundColor: Colors.green))`.
- Ошибки: Colors.red.
- Используются после `await service.xxx()` для feedback'а.

### Bottom sheets
Везде с одинаковой формой:
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: ...
)
```

### Картинки
- `CachedNetworkImage` с placeholder'ом (CircularProgressIndicator).
- Префиксование относительных URL — `ImageHelper.toAbsoluteUrl(url)` (см. [07 §7.x](07-frontend-services-and-domain.md)).
- Сжатие перед upload: 1600px max, q=80, JPEG.

---

## 6.20. Жизненный цикл сценариев (cheat-sheet)

### Сценарий 1: Арендатор регистрируется и подаёт первую заявку

```
LoginScreen → "Зарегистрироваться"
   → RegisterScreen (email, password, ФИО, ИНН, телефон, role=TENANT)
   → POST /api/auth/register → email с кодом
   → ввод 6 цифр (pinput) → POST /api/auth/verify → JWT
   → TenantMainScreen (на вкладке "Карта")
   → пользователь скроллит карту, тапает помещение
   → MapScreen bottomSheet "Подробнее"
   → PropertyDetailsScreen
      • logPropertyView() автоматом
      • кнопка "Подать заявку"
   → Диалог с coverLetter
   → POST /api/applications → SnackBar "Заявка отправлена"
   → переключение на вкладку "Заявки" — заявка появилась
```

### Сценарий 2: Арендодатель добавляет помещение

```
LandlordMainScreen → FAB "+"
   → AddPropertyScreen (5-шаговый wizard)
      • шаг 1: title, MapPickerScreen → coords + address
      • шаг 2..3: финансы, технические поля
      • шаг 4: контакты
      • шаг 5: pickImages → выбор главного фото
   → "Сохранить"
   → POST /api/properties → propertyId
   → POST /api/properties/{id}/images (multipart)
   → если mainPhotoIndex != 0: PUT .../{imageId}/main
   → Navigator.pop(true) → MyPropertiesScreen.loadProperties()
   → новое объявление в списке
```

### Сценарий 3: Tenant получает push об одобрении заявки

```
[Backend] ApplicationService.updateApplicationStatus(ACCEPTED)
   → NotificationService.sendPushNotification(tenantId, ...)  // сейчас лог-заглушка
   → Property.status = RENTED
[Frontend, при следующем входе или pull-to-refresh]
   → MyApplicationsScreen.loadApplications()
   → бейдж заявки сменился на "Одобрено" (зелёный)
   → пользователь тапает "Открыть чат"
   → ChatScreen → getOrCreateRoom → STOMP subscribe
```

---

## 6.21. Известные ограничения UI

1. **Yandex MapKit** требует API-ключ. В коде не виден (вынесен в native config). На локальной сборке нужен валидный ключ.
2. **Нет offline-режима.** При отсутствии сети — пустые экраны/ошибки.
3. **Loading state на длинных операциях** (скоринг 240с) — простой spinner без прогресса.
4. **Нет деep-link'ов.** Push не открывает конкретный экран — приложение просто запускается.
5. **`NotificationService` — заглушка.** FCM не интегрирован.
6. **Чат `currentUserId` извлекается из JWT нестандартно.** Backend кладёт только `sub` (email), Flutter пытается читать `userId`/`id` — работает в основном по совпадению, не идеально.
7. **Глубокая навигация** местами через `Navigator.push` без named routes — нет глобальной навигационной модели.
8. **Form validation** только клиентская — критичные проверки дублируются на backend, как и положено.
9. **`pubspec.yaml`** не содержит i18n-плагинов — все строки hardcoded на русском.
