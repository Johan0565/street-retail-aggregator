# 07. Frontend — сервисы и доменные модели

Документ описывает слой данных Flutter-приложения: HTTP-клиенты, доменные модели, локальное хранилище и хелперы. Это «бизнес-логика клиента» — то, что между UI и backend.

---

## 7.1. Архитектура frontend'а

```
┌──────────────────────────────────────────────────────────────┐
│                    presentation/screens/                      │
│  auth/  tenant/  landlord/  chat/                            │
└─────────────────────────┬────────────────────────────────────┘
                          │ (using)
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                       services/                               │
│  auth │ property │ search_profile │ application │ chat       │
│  favorite │ analytics │ category │ infrastructure │           │
│  notification │ image_helper                                  │
└──────────┬────────────────────────────────┬─────────────────┘
           │ (using)                        │ (using)
           ▼                                ▼
┌─────────────────────────┐    ┌────────────────────────────┐
│       domain/            │    │   FlutterSecureStorage     │
│  Property + PropertyImage│    │   (jwt_token, user_role,   │
│  ScoredProperty +        │    │    saved_accounts,         │
│   ScoreBreakdown         │    │    viewed_property_ids,    │
│  SearchProfile           │    │    remember_me, ...)       │
│  Application             │    └────────────────────────────┘
│  ChatRoom + ChatMessage  │
│  BusinessCategory        │    ┌────────────────────────────┐
│  SavedAccount            │    │      config/               │
│  UserProfile             │    │  ApiConfig (baseUrl/wsUrl) │
│  PropertyFilter          │    └────────────────────────────┘
└──────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────┐
│            HTTP (Dio) / WebSocket (STOMP)                     │
│            ↓                                                  │
│            Backend api.magomedov.online                       │
└──────────────────────────────────────────────────────────────┘
```

**Подход:**
- **Без state management фреймворка** (нет Provider/Riverpod/Bloc). Каждый экран — `StatefulWidget` со своим состоянием. Шеринг — через `GlobalKey` + публичные методы.
- **Один сервис — один файл.** Сервисы — это HTTP-клиенты с `Dio`, без бизнес-логики в духе orchestrator'ов.
- **Доменные модели — простые DTO** с `fromJson`/`toJson`.
- **Безопасное хранилище** — `FlutterSecureStorage` (Keychain на iOS, EncryptedSharedPreferences на Android).

---

## 7.2. `ApiConfig` — точка переключения окружений

[`api_config.dart`](../frontend/lib/src/config/api_config.dart)

```dart
class ApiConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8080';   // Android emulator → host loopback
    }
    return 'http://127.0.0.1:8080';
  }

  static String get apiUrl => '$baseUrl/api';

  static String get wsUrl {
    final base = baseUrl;
    if (base.startsWith('https://')) {
      return 'wss://${base.substring(8)}/ws';
    }
    return 'ws://${base.substring(7)}/ws';
  }
}
```

### Логика

1. **`--dart-define=API_BASE_URL=...`** — production-сборка пользуется этим. Команда сборки:
```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.magomedov.online
```
2. **Android-эмулятор** — особый случай: `10.0.2.2` это alias для хост-машины, а `localhost` указывал бы на саму ВМ эмулятора.
3. **Десктоп/iOS-симулятор** — обычный `127.0.0.1`.
4. **`wsUrl`** автоматически выбирает `ws://` или `wss://` по схеме `baseUrl`.

Все сервисы используют `ApiConfig.apiUrl` (с префиксом `/api`) или `ApiConfig.baseUrl` (без префикса — для endpoints вроде `/uploads/...`).

---

## 7.3. Доменные модели

### 7.3.1. `Property` + `PropertyImage`

[`property.dart`](../frontend/lib/src/domain/property.dart)

Зеркало backend-сущности `Property`. **Не все 36 полей backend'а** — только то, что нужно UI:

```dart
class Property {
  final int id;
  final String title;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final double areaSqm;
  final double pricePerMonth;
  final String? status;     // PUBLISHED, ARCHIVED, ...

  final String? propertyType;
  final String? dealType;

  final int powerKw;
  final bool hasWater;
  final bool hasVentilation;
  final bool hasSeparateEntrance;
  final bool hasWc;
  final bool hasParking;
  final bool hasLoadingZone;
  final double? ceilingHeight;
  final String? repairState;
  final String? layout;

  final String? contactName;
  final String? contactPhone;

  final String? cadastralNumber;
  final String? accessType;
  final String? heatingType;
  final String? furnitureState;
  final bool? isOccupied;
  final String? metroStation;
  final int? timeToMetro;

  final List<PropertyImage> images;
  // ...
}

class PropertyImage {
  final int id;
  final String imageUrl;
  final bool isMain;
}
```

**Защитный fromJson** — все поля с дефолтами `?? 0`, `?? ''`, `?? false`. Это гарантирует, что если backend вернёт частичный JSON (например, без images в списке), Dart-конструктор не упадёт.

```dart
factory Property.fromJson(Map<String, dynamic> json) {
  return Property(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title']?.toString() ?? 'Без названия',
    // ...
    images: (json['images'] as List<dynamic>?)
            ?.map((e) => PropertyImage.fromJson(e as Map<String, dynamic>))
            .toList() ?? const [],
  );
}
```

### 7.3.2. `ScoredProperty` + `ScoreBreakdown` (и подклассы)

[`search_profile.dart`](../frontend/lib/src/domain/search_profile.dart) (там же)

Самая большая модель. Зеркало backend-`ScoredPropertyDto`. **Содержит 16 классов** (главный + 5 Part'ов + 4 Ref'a + 4 Item'а + enum).

```dart
enum ScoringDataStatus { complete, overpassUnavailable }

class ScoredProperty {
  final Property property;
  final int totalScore;
  final int financialScore;
  final int technicalScore;
  final int competitorScore;
  final int synergyScore;
  final int transportScore;
  final List<String> directCompetitorNames;
  final List<String> synergyNeighborNames;
  final String matchLabel;
  final String matchColor;
  final ScoreBreakdown? breakdown;
  final ScoringDataStatus dataStatus;
  final DateTime? computedAt;
  final String? algorithmVersion;

  bool get isPartial => dataStatus == ScoringDataStatus.overpassUnavailable;

  Color get flutterColor {
    switch (matchColor) {
      case 'green':  return const Color(0xFF22C55E);
      case 'yellow': return const Color(0xFFF59E0B);
      case 'gray':   return const Color(0xFF94A3B8);
      default:       return const Color(0xFFEF4444);
    }
  }

  String get markerEmoji {
    if (isPartial) return '⚠️';
    if (totalScore >= 75) return '🔥';
    if (totalScore >= 50) return '👍';
    if (totalScore >= 25) return '⚠️';
    return '❌';
  }
}
```

### `ScoreBreakdown` — детализация

```dart
class ScoreBreakdown {
  final FinancialPart? financial;
  final TechnicalPart? technical;
  final CompetitorPart? competitor;
  final SynergyPart? synergy;
  final TransportPart? transport;
}

class FinancialPart {
  final double budgetPoints;    // 0-10
  final String? budgetReason;
  final double areaPoints;      // 0-10
  final String? areaReason;
}

class TechnicalItem {
  final String requirement;     // "вода", "мощность", "потолки"
  final double penalty;         // 0 если ок
  final String? reason;
}

class CompetitorRef {
  final String name;
  final double distanceMeters;
  final double weight;
  final double? latitude;       // для перемещения камеры
  final double? longitude;
  final double scoreImpact;     // -7.2: «съел» 7.2 балла
}

class SynergyRef { /* аналогично, scoreImpact >= 0 */ }

class TransportPart {
  final String? nearestName;
  final String nearestType;    // METRO / RAIL / TRAM / BUS / NONE
  final double nearestDistanceMeters;  // -1 если нет
  final String? reason;

  String get typeLabel => switch (nearestType) {
    'METRO' => 'метро',
    'RAIL'  => 'ж/д',
    'TRAM'  => 'трамвай',
    'BUS'   => 'автобус',
    _ => 'нет общественного транспорта',
  };
}
```

### 7.3.3. `SearchProfile`

В том же файле. Зеркало backend-`SearchProfile`.

```dart
class SearchProfile {
  final int id;
  final String name;
  final int? businessCategoryId;
  final String? businessCategoryName;

  final double? minArea, maxArea;
  final double? minBudget, maxBudget;
  final int? minPowerKw;
  final bool? requiresWater, requiresVentilation, requiresSeparateEntrance;
  final bool? requiresWc, requiresParking, requiresLoadingZone;
  final double? minCeilingHeight;

  final double? centerLatitude, centerLongitude;
  final int? searchRadiusMeters;
  final int? synergyRadiusMeters;

  final List<int> desiredNeighborCategoryIds;
  final List<String> desiredNeighborNames;

  final bool isActive;
  final String? createdAt;
}
```

**toJson** — отправляет только non-null поля (через `if (... != null)` в map literal):

```dart
Map<String, dynamic> toJson() => {
  'name': name,
  if (businessCategoryId != null) 'businessCategoryId': businessCategoryId,
  if (minArea != null) 'minArea': minArea,
  // ...
};
```

Это позволяет создавать профиль с частичными критериями — backend интерпретирует null как «без ограничения».

### 7.3.4. `Application` → `ApplicationModel`

[`application_model.dart`](../frontend/lib/src/domain/application_model.dart)

```dart
class ApplicationModel {
  final int id;
  final String status;
  final String coverLetter;
  final String createdAt;
  final Property property;

  final String? tenantName;
  final String? tenantEmail;
  final String? tenantPhone;

  final String? landlordName;
  final String? landlordPhone;

  final String? rejectionReason;
}
```

Соответствует backend `ApplicationResponseDto` с вложенными `Property/Tenant/LandlordShortInfo`, **раскрытыми в плоскую структуру** в Dart — UI с такой удобнее работать (вместо `app.tenant?.name` пишем `app.tenantName`).

### 7.3.5. `ChatRoom` и `ChatMessage`

[`chat_room.dart`](../frontend/lib/src/domain/chat_room.dart) и [`chat_message.dart`](../frontend/lib/src/domain/chat_message.dart)

Простые DTO.

```dart
class ChatRoom {
  final int id;
  final int applicationId;
  final int landlordId; final String landlordName;
  final int tenantId; final String tenantName;
}

class ChatMessage {
  final int id;
  final int chatRoomId;
  final int senderId; final String senderName;
  final String content;
  final bool isRead;
  final DateTime? timestamp;
}
```

`timestamp` парсится через `DateTime.tryParse` — устойчиво к пустому/невалидному значению.

### 7.3.6. `BusinessCategory`

[`business_category.dart`](../frontend/lib/src/domain/business_category.dart)

```dart
class BusinessCategory {
  final int id;
  final String name;
}
```

Минимальный, без `subCategories` — Dropdown'ы используют плоский список (`getAllCategories` в `CategoryService`).

### 7.3.7. `UserProfile`

[`user_profile.dart`](../frontend/lib/src/domain/user_profile.dart)

Общий профиль для tenant и landlord (с разными ключами в JSON):

```dart
class UserProfile {
  final int id;
  final String name;          // или companyName для landlord
  final String inn;
  final String phone;
  final String businessCategory;
  final int? businessCategoryId;
  final String? avatarUrl;
}

factory UserProfile.fromJson(Map<String, dynamic> json) {
  // ...
  return UserProfile(
    name: json['name'] ?? json['companyName'] ?? 'Имя не указано',
    // ...
  );
}
```

Один класс работает с обоими endpoint'ами `/api/profiles/tenant/me` и `/api/profiles/landlord/me` благодаря fallback на `companyName`.

### 7.3.8. `SavedAccount` — мульти-аккаунт

[`saved_account.dart`](../frontend/lib/src/domain/saved_account.dart)

```dart
class SavedAccount {
  final String email;
  final String role;
  final String token;
  final String? displayName;
  final DateTime lastUsedAt;

  String get initials {
    // Алгоритм: первая буква имени/email + первая буква второго слова,
    // или одна буква если слов нет
    final source = (displayName != null && displayName!.trim().isNotEmpty)
        ? displayName!.trim() : email;
    // ... regex чистка + split + первые буквы
  }

  static List<SavedAccount> decodeList(String? raw) { /* jsonDecode */ }
  static String encodeList(List<SavedAccount> accounts) { /* jsonEncode */ }
}
```

Сохраняется в `FlutterSecureStorage` как **сериализованный JSON-массив**. Хранит **JWT каждого аккаунта** — позволяет переключаться между ними без повторного логина (пока токены живы).

### 7.3.9. `PropertyFilter` — UI-фильтры карты

[`property_filter.dart`](../frontend/lib/src/domain/property_filter.dart)

```dart
enum ScoreBucket { low, medium, high }

class PropertyFilter {
  final double? minPrice, maxPrice;
  final double? minArea, maxArea;
  final String? metroStation;
  final Set<String> propertyTypes;   // {'RETAIL', 'OFFICE'}
  final bool onlyFree;               // isOccupied == false
  final Set<ScoreBucket> scoreBuckets;

  bool get isActive => /* любое поле задано */;
  int get activeCount => /* для badge "5 фильтров активно" */;

  List<Property> apply(List<Property> properties, {int? Function(int)? scoreOf}) {
    return properties.where((p) {
      if (minPrice != null && p.pricePerMonth < minPrice!) return false;
      // ... все проверки
      if (scoreBuckets.isNotEmpty) {
        final score = scoreOf?.call(p.id);
        if (score == null) return false;
        final hit = scoreBuckets.any((b) => b.contains(score));
        if (!hit) return false;
      }
      return true;
    }).toList();
  }
}
```

**Клиентская фильтрация** — backend возвращает все PUBLISHED, фронт фильтрует в памяти. Это OK для текущего масштаба (десятки помещений), при росте стоит перенести часть фильтров в API.

**Score buckets:**
- low: 0–40
- medium: 40–80
- high: 80–∞

---

## 7.4. Сервисы

Все сервисы построены по единому паттерну:

```dart
class XxxService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,   // или baseUrl без /api
    connectTimeout: const Duration(seconds: 5..30),
    receiveTimeout: const Duration(seconds: 5..240),
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<X> someMethod(...) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get/post/put/delete(
        '/endpoint',
        data: ...,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return X.fromJson(response.data);
      }
      return null;  // или [] или false
    } catch (e) {
      print('Ошибка: $e');
      return null;
    }
  }
}
```

**Особенности:**
- **Try-catch swallow**. Сервисы возвращают `null`/`[]`/`false` вместо проброса исключений. Это упрощает UI-код, но скрывает причину ошибки. Исключение: `SearchProfileService.getScoredProperties` бросает наружу — UI должен отличать «пусто» от «таймаут».
- **Таймауты разные** под use-case:
  - Auth/Property — 5–30с.
  - SearchProfile.getScoredProperties — **240с** (тяжёлый Overpass-батч).
  - explainScore — 45с (LLM может думать).
  - Image upload — 60с (несколько MB).

### 7.4.1. `AuthService` — авторизация, мульти-аккаунт

[`auth_service.dart`](../frontend/lib/src/services/auth_service.dart) — самый большой сервис.

**Хранит в `FlutterSecureStorage`:**

| Ключ                  | Значение                                          |
|-----------------------|---------------------------------------------------|
| `jwt_token`           | Текущий активный JWT                              |
| `user_role`           | `TENANT` или `LANDLORD`                           |
| `active_account_email`| Email активного аккаунта                          |
| `saved_accounts`      | JSON-массив `SavedAccount[]`                      |
| `remember_me`         | `'true'`/`'false'`                                |
| `saved_email`         | Email для предзаполнения формы логина             |

**Главные методы:**

```dart
// Регистрация / верификация / логин
Future<bool> register(String email, String password, String role, String name, String inn, String phone);
Future<bool> verifyEmail(String email, String code);
Future<bool> login(String email, String password, bool rememberMe);
Future<bool> resendCode(String email);

// Сессия
Future<String?> checkAutoLogin();          // remember_me=true && токен не истёк
Future<void> logout();                     // очистка активной сессии, savedAccounts остаются
Future<String?> getToken();
Future<String?> getUserRole();

// Профиль
Future<UserProfile?> getCurrentUserProfile();  // выбирает endpoint по роли
Future<bool> updateProfile(String name, String phone, int? categoryId);
Future<String?> uploadAvatar(File file);   // multipart
Future<bool> deleteAvatar();

// Мульти-аккаунт
Future<List<SavedAccount>> getSavedAccounts();
Future<String?> getActiveEmail();
Future<String?> resumeSavedAccount(String email);   // переключение без логина
Future<void> removeSavedAccount(String email);
```

**`checkAutoLogin`:**
```dart
Future<String?> checkAutoLogin() async {
  final rememberMe = await _storage.read(key: 'remember_me');
  if (rememberMe == 'true') {
    final token = await _storage.read(key: 'jwt_token');
    final role = await _storage.read(key: 'user_role');
    if (token != null && role != null && !_isTokenExpired(token)) {
      return role;  // успех!
    }
  } else {
    await logout();  // не было «запомнить» — стираем сессию
  }
  return null;
}
```

**`resumeSavedAccount`:**
```dart
Future<String?> resumeSavedAccount(String email) async {
  final accounts = await getSavedAccounts();
  final match = accounts.where((a) => a.email == email).toList();
  if (match.isEmpty) return null;
  final account = match.first;
  if (_isTokenExpired(account.token)) return null;

  await _activateSession(email, account.token, account.role);
  await _upsertSavedAccount(account.copyWith(lastUsedAt: DateTime.now()));
  return account.role;
}
```

После `login` с `rememberMe=true` — аккаунт сохраняется в `savedAccounts` с текущим JWT. Позже можно переключиться на него без ввода пароля, пока JWT не истёк.

### 7.4.2. `PropertyService` — CRUD помещений

[`property_service.dart`](../frontend/lib/src/services/property_service.dart)

```dart
// Каталог
Future<Property?> getPropertyById(int id);
Future<List<Property>> getAllProperties();
Future<List<Property>> getMyProperties();        // только LANDLORD
Future<List<Property>> getFavoriteProperties();  // /properties/favorites

// Создание / удаление
Future<int?> createProperty({...35+ named params...});
Future<bool> deleteProperty(int propertyId);    // soft-delete

// Картинки
Future<bool> uploadPropertyImages(int propertyId, List<File> files);
Future<bool> deletePropertyImage(int propertyId, int imageId);
Future<bool> setMainPropertyImage(int propertyId, int imageId);

// Скоринг
Future<ScoredProperty?> scoreProperty(int propertyId, {int? profileId, bool force = false});
Future<String?> explainScore(int propertyId, {int? profileId});  // AI

// Избранное
Future<bool> toggleFavorite(int propertyId);
```

**Особенности:**

- **`createProperty`** имеет 35+ named-параметров (зеркало `CreatePropertyRequest`). Возвращает `int?` — id, нужный для последующего upload фото.
- **`uploadPropertyImages`** использует `FormData.fromMap({ 'files': [MultipartFile.fromFile(...)] })`. Таймауты увеличены до 60с.
- **`explainScore`** имеет `receiveTimeout: 45с` — LLM иногда долго думает.
- **`getPropertyById`** догружает полный объект с картинками — потому что `/api/properties` (списочный) может вернуть объект без `images` из-за обрезки.

### 7.4.3. `SearchProfileService`

[`search_profile_service.dart`](../frontend/lib/src/services/search_profile_service.dart)

```dart
class SearchProfileService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 240),  // ⚠️ длинный таймаут
    sendTimeout: const Duration(seconds: 30),
  ));

  Future<List<SearchProfile>> getMyProfiles();
  Future<SearchProfile?> createProfile(Map<String, dynamic> data);
  Future<SearchProfile?> updateProfile(int id, Map<String, dynamic> data);
  Future<bool> deleteProfile(int id);

  // ⭐ Тяжёлый метод — может занимать минуты
  Future<List<ScoredProperty>> getScoredProperties(int profileId);
}
```

**Комментарий из кода:**

> 240 секунд — запас для тяжёлой операции /scored-properties: 20+ помещений × 2 Overpass-запроса каждое, под нагрузкой Overpass.de отвечает 10–25с. С пулом 8 и параллелизацией IO внутри помещения батч укладывается в 30–60с штатно, до 180с — в редких пиках.

**`getScoredProperties` — единственный сервис, который пробрасывает `DioException`** наружу. UI отличает «пусто» (нет подходящих) от «не ответил» (таймаут).

### 7.4.4. `ApplicationService`

[`application_service.dart`](../frontend/lib/src/services/application_service.dart)

```dart
Future<bool> createApplication(int propertyId, String coverLetter);
Future<List<ApplicationModel>> getMyApplications();         // tenant
Future<List<ApplicationModel>> getIncomingApplications();   // landlord
Future<bool> updateApplicationStatus(int id, String newStatus, {String? rejectionReason});
Future<bool> deleteApplication(int id);
```

Простой CRUD без особенностей.

### 7.4.5. `ChatService` — REST + WebSocket

[`chat_service.dart`](../frontend/lib/src/services/chat_service.dart)

```dart
class ChatService {
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  StompClient? _stompClient;

  Future<ChatRoom> getOrCreateRoom(int applicationId);
  Future<List<ChatMessage>> getMessages(int roomId);
  Future<ChatMessage> sendMessage(int roomId, String content);

  void connectStomp(int roomId, Function(ChatMessage) onMessageReceived);
  void disconnectStomp();
}
```

**STOMP-подключение:**

```dart
void connectStomp(int roomId, Function(ChatMessage) onMessage) async {
  final token = await _storage.read(key: 'jwt_token');

  _stompClient = StompClient(
    config: StompConfig(
      url: ApiConfig.wsUrl,    // ws:// или wss:// автодетект
      onConnect: (StompFrame frame) {
        _stompClient?.subscribe(
          destination: '/topic/chat/$roomId',
          callback: (frame) {
            if (frame.body != null) {
              final json = jsonDecode(frame.body!);
              final message = ChatMessage.fromJson(json);
              onMessage(message);
            }
          },
        );
      },
      stompConnectHeaders: {'Authorization': 'Bearer $token'},
      webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
    ),
  );
  _stompClient?.activate();
}
```

**Двойной канал:**
- **Отправка** — через REST POST `/api/chat/rooms/{roomId}/messages`. Сервер сохраняет + broadcast.
- **Получение** — через STOMP subscribe `/topic/chat/{roomId}`. Real-time без поллинга.

Это разделение упрощает auth (REST уже валидирует JWT, не нужно дублировать в STOMP).

### 7.4.6. `FavoriteService`

[`favorite_service.dart`](../frontend/lib/src/services/favorite_service.dart)

```dart
Future<bool> addToFavorites(int propertyId);
Future<bool> removeFromFavorites(int propertyId);
Future<List<Property>> getMyFavorites();
```

Дублирует часть `PropertyService.toggleFavorite/getFavoriteProperties` — обёртка существует исторически.

### 7.4.7. `AnalyticsService`

[`analytics_service.dart`](../frontend/lib/src/services/analytics_service.dart)

```dart
Future<AnalyticsDto?> getMyAnalytics();
Future<AnalyticsDto?> getPropertyAnalytics(int propertyId);
Future<void> logPropertyView(int propertyId);  // fire-and-forget
```

**`AnalyticsDto`** содержит `viewsByDate`/`favoritesByDate`/`applicationsByDate` — `Map<String, int>` для графиков fl_chart.

**Локальный `ViewedPropertiesStore`:**

```dart
class ViewedPropertiesStore {
  Set<int>? _cache;
  Future<Set<int>> load();
  Future<void> add(int propertyId);
  bool isViewedSync(int propertyId);  // для UI без await
}
```

Сохраняет ID просмотренных помещений в `FlutterSecureStorage` (`viewed_property_ids` — строка с запятыми). Используется на карте для затемнения меток уже посмотренных помещений.

### 7.4.8. `CategoryService`

[`category_service.dart`](../frontend/lib/src/services/category_service.dart)

```dart
Future<List<BusinessCategory>> getCategories();              // tree (без вложенности)
Future<List<Map<String, dynamic>>> getAllCategories();       // flat для Dropdown
```

**Fallback на hardcoded список** при ошибке:

```dart
List<BusinessCategory> _getFallbackCategories() {
  return [
    BusinessCategory(id: 1, name: 'Кофейня / Пекарня'),
    BusinessCategory(id: 2, name: 'Пункт выдачи заказов (ПВЗ)'),
    BusinessCategory(id: 3, name: 'Продуктовый магазин'),
    BusinessCategory(id: 4, name: 'Аптека'),
    BusinessCategory(id: 5, name: 'Салон красоты / Барбершоп'),
    BusinessCategory(id: 6, name: 'Одежда и обувь'),
    BusinessCategory(id: 7, name: 'Спортзал / Фитнес'),
  ];
}
```

Это позволяет UI работать даже когда backend недоступен (например, при первом запуске на эмуляторе без сети) — но id в fallback не соответствуют реальным id в БД, что вызовет ошибки при сохранении.

### 7.4.9. `InfrastructureService`

[`infrastructure_service.dart`](../frontend/lib/src/services/infrastructure_service.dart)

```dart
class PoiDto {
  final String name;
  final String category;       // 'metro', 'cafe', 'university'
  final double distanceMeters;
}

class InfrastructureService {
  Future<List<PoiDto>> getInfrastructureNearby(double lat, double lon);
}
```

Простой клиент к `/api/infrastructure?lat=...&lon=...&radius=500`. Используется на карточке помещения для секции «Что рядом».

### 7.4.10. `NotificationService` — заглушка под FCM

[`notification_service.dart`](../frontend/lib/src/services/notification_service.dart)

```dart
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Future<void> initialize() async {
    // TODO: await Firebase.initializeApp();
    debugPrint('🔔 [FCM STUB] NotificationService initialized.');
  }

  void handleIncomingMessages() {
    // TODO: FirebaseMessaging.onMessage.listen(...);
    debugPrint('🔔 [FCM STUB] Listening for incoming messages.');
  }
}
```

**Текущее состояние:** оба метода — заглушки. Singleton, инициализируется в `main.dart`.

### 7.4.11. `ImageHelper` — выбор и обработка фото

[`image_helper.dart`](../frontend/lib/src/services/image_helper.dart)

```dart
class ImageHelper {
  // Префиксует относительный URL базовым
  static String? toAbsoluteUrl(String? relativeOrAbsolute) {
    if (relativeOrAbsolute == null) return null;
    if (relativeOrAbsolute.startsWith('http')) return relativeOrAbsolute;
    return '${ApiConfig.baseUrl}$relativeOrAbsolute';
  }

  // BottomSheet с выбором источника + multi-pick + сжатие
  static Future<List<File>> pickImages(BuildContext context, {bool allowMultiple = false});
}
```

**`pickImages`:**

1. Показывает `BottomSheet` с двумя кнопками: «Из галереи» / «Сделать фото».
2. Если галерея + `allowMultiple` → `_picker.pickMultiImage()`.
3. Иначе → `_picker.pickImage(source: ...)`.
4. **Каждую картинку сжимает** через `FlutterImageCompress`:
   ```dart
   await FlutterImageCompress.compressAndGetFile(
     source.absolute.path,
     '${tmpDir.path}/${timestamp}.jpg',
     quality: 80,
     minWidth: 1600, minHeight: 1600,
     format: CompressFormat.jpeg,
   );
   ```
5. Возвращает `List<File>` готовых к upload.

**Почему сжатие:** мобильные камеры дают 3–10MB JPG; backend лимит 5MB на файл. Сжатие до ~1600px / q=80 даёт обычно 200–800KB и проходит через лимит с запасом.

---

## 7.5. Безопасное хранилище — `FlutterSecureStorage`

**Все ключи проекта:**

| Ключ                    | Назначение                                                              |
|-------------------------|-------------------------------------------------------------------------|
| `jwt_token`             | Текущий активный JWT                                                    |
| `user_role`             | Роль текущего пользователя (`TENANT`/`LANDLORD`)                        |
| `active_account_email`  | Email активного аккаунта                                                |
| `saved_accounts`        | JSON-массив `SavedAccount` (мульти-аккаунт)                             |
| `remember_me`           | `'true'`/`'false'` — поведение при следующем запуске                    |
| `saved_email`           | Email для предзаполнения формы логина                                   |
| `viewed_property_ids`   | ID просмотренных помещений (для затемнения меток на карте)              |

**На разных платформах:**
- **iOS** — Keychain Services.
- **Android** — EncryptedSharedPreferences.
- **Windows/macOS/Linux** — DPAPI/Keychain/Secret Service.
- **Web** — обычный localStorage (не secure).

Это критично для JWT: токен живёт 24 часа, и компрометация = доступ к аккаунту. Plain SharedPreferences не подходит.

---

## 7.6. Dio: единый HTTP-стек

Все сервисы используют `Dio` с похожей конфигурацией:

```dart
final Dio _dio = Dio(BaseOptions(
  baseUrl: ApiConfig.apiUrl,
  connectTimeout: const Duration(seconds: 30),
  receiveTimeout: const Duration(seconds: 30),
  sendTimeout: const Duration(seconds: 30),
));
```

**Авторизация:** на каждый запрос вручную:
```dart
final token = await _storage.read(key: 'jwt_token');
final response = await _dio.get('/endpoint', options: Options(
  headers: {'Authorization': 'Bearer $token'},
));
```

**Замечание:** можно было бы использовать `Dio Interceptor`, который автоматически вставляет токен — но в текущем коде это сделано вручную в каждом методе. Кандидат на рефакторинг.

---

## 7.7. WebSocket / STOMP клиент

Только `ChatService` использует WS. Подробности — §7.4.5. Подключение **per-room**: при выходе из `ChatScreen` → `_chatService.disconnectStomp()`. Не персистентное.

**Альтернатива:** глобальный singleton-StompClient, который держит подключение всё время приложения и подписывается на все мои `chat_rooms` сразу. Это позволило бы получать сообщения даже когда экран чата не открыт — но требует push-уведомлений для оффлайн-сценария.

---

## 7.8. Жизненный цикл данных

### Логин

```
LoginScreen
  → AuthService.login(email, password, rememberMe)
     → POST /api/auth/login
     → _activateSession(email, token, role)
        — write jwt_token, user_role, active_account_email
     → write remember_me = rememberMe
     → if rememberMe: _upsertSavedAccount(SavedAccount(...))
  → role вернулся
  → Navigator → TenantMainScreen / LandlordMainScreen
```

### Просмотр помещения арендатором

```
MapScreen tap маркер
  → bottomSheet
  → "Подробнее"
  → Navigator.push(PropertyDetailsScreen)
     → initState():
       — AnalyticsService.logPropertyView(id)  // backend + ViewedPropertiesStore
       — _checkIfFavorite()
       — _fetchFullProperty() — догрузка images
     → пользователь тапает "Оценить"
        → PropertyService.scoreProperty(id, profileId, force=false)
        → отображение breakdown в UI
     → пользователь тапает "AI-объяснение"
        → PropertyService.explainScore(id, profileId) — до 45с
        → отображение в bottomSheet
```

### Создание объявления

```
LandlordMainScreen FAB "+"
  → AddPropertyScreen (5-step wizard)
     → каждый шаг: GlobalKey<FormState>.validate()
     → шаг 5: ImageHelper.pickImages(allowMultiple: true)
        — выбор источника
        — multi-pick
        — сжатие 1600px/q=80 для каждой
  → submit:
     1. PropertyService.createProperty(...) → propertyId
     2. PropertyService.uploadPropertyImages(propertyId, files)
        — multipart, timeout 60с
     3. setMainPropertyImage если нужно
  → Navigator.pop(true) → MyPropertiesScreen.loadProperties()
```

### Real-time чат

```
ChatScreen initState
  → ChatService.getOrCreateRoom(applicationId) — REST
  → ChatService.getMessages(roomId) — REST
  → ChatService.connectStomp(roomId, onMessage) — WS

Пользователь печатает + отправляет:
  → ChatService.sendMessage(roomId, content) — REST POST
     → backend saves + broadcast /topic/chat/{roomId}
  → WS callback → onMessage(ChatMessage)
     → dedupe by id (не добавлять, если REST уже вернул)

ChatScreen dispose
  → ChatService.disconnectStomp()
```

---

## 7.9. Известные ограничения

1. **Нет state management фреймворка.** Шеринг состояния между экранами — через `GlobalKey`. Работает, но плохо масштабируется.
2. **Каждый сервис создаёт свой `Dio`-инстанс.** Нет общего interceptor'a для авторизации/логирования/retry — приходится дублировать в каждом методе.
3. **Нет глобального error handling'а.** Каждый сервис делает свой try-catch и возвращает `null`. UI получает «не загрузилось» без причины.
4. **CategoryService fallback** — id'шки в hardcoded списке не совпадают с реальными в БД. Приведёт к 500-ошибке при попытке создать SearchProfile с такой категорией.
5. **JSON-парсинг без code-generation.** Все `fromJson` написаны вручную. При росте моделей стоит добавить `json_serializable` + `build_runner`.
6. **Web не поддерживается** на 100% — `Platform.isAndroid` в `ApiConfig` бросит на web, защищено `!kIsWeb`. Но `FlutterSecureStorage` на web — это просто localStorage, что небезопасно.
7. **Нет global STOMP connection.** Чат работает только при открытом `ChatScreen`. Сообщения, пришедшие в офлайне, видны только при ручном переходе.
8. **i18n не подключён.** Все строки на русском, хардкод.
9. **Token refresh нет.** После 24ч пользователь должен logout/login или ждать `resumeSavedAccount` с сохранённым токеном (если он успел сохраниться — что нелогично, потому что у нас всегда один и тот же JWT).
10. **`Dio` без retry/circuit-breaker.** Сбой сети = моментальная ошибка.
