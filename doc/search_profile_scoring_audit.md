# Аудит процесса создания «Проекта поиска» (Search Profile) и интеграции со скорингом

## 1. Frontend-флоу (Flutter)

Создание проекта поиска реализовано в `CreateSearchProfileScreen` на базе виджета `Stepper`, состоящего из 3 шагов. 

### Данные, собираемые на каждом шаге:
1. **Шаг 1: Основное** 
   - `name`: Название проекта поиска (TextController).
   - `businessCategoryId`: ID категории бизнеса (DropdownButton).
2. **Шаг 2: Финансы**
   - `minBudget`, `maxBudget`: Диапазон бюджета в рублях (TextControllers).
   - `minArea`, `maxArea`: Диапазон площади в м² (TextControllers).
3. **Шаг 3: Технические**
   - `minPowerKw`: Минимальная электрическая мощность в кВт (TextController).
   - `minCeilingHeight`: Минимальная высота потолков в метрах — **новый параметр**.
   - Булевы флаги (SwitchListTile):
     - `requiresWater`: Нужна мокрая точка.
     - `requiresVentilation`: Нужна вытяжка / вентиляция.
     - `requiresSeparateEntrance`: Нужен отдельный вход.
     - `requiresWc`: Нужен санузел — **новый параметр**.
     - `requiresParking`: Нужна парковка рядом — **новый параметр**.
     - `requiresLoadingZone`: Нужна зона разгрузки/погрузки — **новый параметр**.

### Формирование JSON для отправки на бэкенд
В методе `_save()` данные собираются в `Map<String, dynamic>`, которая затем автоматически конвертируется в JSON сервисом при отправке. Новые технические параметры явно передаются в мапе (числовые значения парсятся, а булевы передаются напрямую):

```dart
final data = <String, dynamic>{
  'name': _nameController.text.trim(),
  if (_selectedCategoryId != null) 'businessCategoryId': _selectedCategoryId,
  if (_minAreaController.text.isNotEmpty) 'minArea': double.tryParse(_minAreaController.text),
  if (_maxAreaController.text.isNotEmpty) 'maxArea': double.tryParse(_maxAreaController.text),
  if (_minBudgetController.text.isNotEmpty) 'minBudget': double.tryParse(_minBudgetController.text),
  if (_maxBudgetController.text.isNotEmpty) 'maxBudget': double.tryParse(_maxBudgetController.text),
  if (_minPowerController.text.isNotEmpty) 'minPowerKw': int.tryParse(_minPowerController.text),
  if (_minCeilingController.text.isNotEmpty) 'minCeilingHeight': double.tryParse(_minCeilingController.text), // <- новый параметр
  
  'requiresWater': _requiresWater,
  'requiresVentilation': _requiresVentilation,
  'requiresSeparateEntrance': _requiresSeparateEntrance,
  'requiresWc': _requiresWc,                   // <- новый параметр
  'requiresParking': _requiresParking,         // <- новый параметр
  'requiresLoadingZone': _requiresLoadingZone, // <- новый параметр
};
```

---

## 2. Прием данных на Backend (Controller & DTO)

### Эндпоинт в Controller
Запрос приходит на `POST /api/search-profiles`. Контроллер защищен аннотацией `@PreAuthorize("hasRole('TENANT')")`. Он извлекает ID текущего пользователя из JWT-токена (через `Principal`) и передает запрос в сервисный слой:

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

### Структура DTO и статус валидации
Класс `CreateSearchProfileRequest` содержит все необходимые поля, включая новые технические критерии. Однако **строгая валидация полей на уровне DTO (Jakarta Validation) отсутствует** — в коде нет аннотаций `@NotBlank`, `@NotNull` или `@Min`.

```java
@Data
public class CreateSearchProfileRequest {
    private String name;                        // Название проекта
    private Long businessCategoryId;            // ID бизнес-категории

    // --- Финансовые критерии ---
    private BigDecimal minArea;                 // Мин. площадь, м²
    // ...

    // --- Технические критерии ---
    private Integer minPowerKw;                 // Минимальная мощность, кВт
    private Boolean requiresWater;              // Нужна мокрая точка
    private Boolean requiresVentilation;        // Нужна вытяжка
    private Boolean requiresSeparateEntrance;   // Нужен отдельный вход
    private Boolean requiresWc;                 // Нужен санузел
    private Boolean requiresParking;            // Нужна парковка
    private Boolean requiresLoadingZone;        // Нужна зона разгрузки
    private BigDecimal minCeilingHeight;        // Мин. высота потолков, м
    // ...
}
```
*Аудит выявляет точку роста: добавление `@Valid` в контроллере и аннотаций в DTO поможет избежать сохранения профилей с некорректными данными (например, пустых строк).*

---

## 3. Бизнес-логика создания (SearchProfileService)

Бизнес-логика создания реализуется в классе `SearchProfileService`. 

### Привязка Tenant и маппинг BusinessCategory
Метод `buildProfileFromRequest` выполняет перенос данных из DTO в Entity. 
- **Авторизованный пользователь (Tenant)** привязывается напрямую путем передачи объекта `User`, который загружается из базы по `tenantId` из токена.
- **Бизнес-категория** передается с фронта только как числовой ID (`businessCategoryId`). Бэкенд делает запрос к `businessCategoryRepository`, получает полноценную сущность `BusinessCategory` и связывает её с создаваемым профилем.

```java
@Transactional
public SearchProfile createSearchProfile(Long tenantId, CreateSearchProfileRequest request) {
    User tenant = userRepository.findById(tenantId)
            .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

    SearchProfile profile = buildProfileFromRequest(request, tenant);
    return searchProfileRepository.save(profile);
}

private SearchProfile buildProfileFromRequest(CreateSearchProfileRequest request, User tenant) {
    BusinessCategory category = null;
    if (request.getBusinessCategoryId() != null) {
        category = businessCategoryRepository.findById(request.getBusinessCategoryId())
                .orElseThrow(() -> new RuntimeException("Категория не найдена"));
    }

    return SearchProfile.builder()
            .tenant(tenant)
            .name(request.getName())
            .businessCategory(category)
            // маппинг всех метрик
            .requiresWc(request.getRequiresWc())
            .requiresParking(request.getRequiresParking())
            .requiresLoadingZone(request.getRequiresLoadingZone())
            .minCeilingHeight(request.getMinCeilingHeight())
            // ...
            .isActive(true)
            .build();
}
```

---

## 4. Интеграция со скорингом (PropertyScoringService)

Созданный `SearchProfile` напрямую выступает базисом для AI-скоринга помещений. При вызове эндпоинта подбора помещений (`/api/search-profiles/{id}/scored-properties`) профиль передается в метод `scoreAndRankProperties`, а затем в `scoreInternal`, где балл рассчитывается на основе трех компонентов:

```java
private ScoredPropertyDto scoreInternal(SearchProfile profile, Property property,
                                         List<BusinessCategory> allCategories) {
    int financial   = calculateFinancialScore(profile, property);
    int technical   = calculateTechnicalScore(profile, property); // Ключевой метод!
    int competitors = calculateCompetitorScore(profile, property, allCategories);
    int total       = financial + technical + competitors;
    
    // Возвращается DTO с детальной разбивкой
}
```

### Пример вычета баллов за несоответствие требованиям
В методе `calculateTechnicalScore` реализована **штрафная модель** (от 0 до 20 баллов). Изначально помещению дается максимальный балл, а затем за каждое несовпадение между требованиями профиля арендатора (`profile`) и характеристиками помещения (`property`) физически вычитаются баллы. 

Новые технические параметры, добавленные на UI, корректно обрабатываются в скоринге:

```java
private int calculateTechnicalScore(SearchProfile profile, Property property) {
    int score = MAX_TECHNICAL_SCORE; // 20

    // Старые параметры
    if (Boolean.TRUE.equals(profile.getRequiresWater()) && !Boolean.TRUE.equals(property.getHasWater()))
        score -= 4;
    if (Boolean.TRUE.equals(profile.getRequiresVentilation()) && !Boolean.TRUE.equals(property.getHasVentilation()))
        score -= 4;
        
    // НОВЫЕ ПАРАМЕТРЫ агрессивно штрафуют помещение:
    if (Boolean.TRUE.equals(profile.getRequiresWc()) && !Boolean.TRUE.equals(property.getHasWc()))
        score -= 3;
    if (Boolean.TRUE.equals(profile.getRequiresParking()) && !Boolean.TRUE.equals(property.getHasParking()))
        score -= 2;
    if (Boolean.TRUE.equals(profile.getRequiresLoadingZone()) && !Boolean.TRUE.equals(property.getHasLoadingZone()))
        score -= 2;
        
    // Штраф за низкие потолки (сравнение BigDecimal)
    if (profile.getMinCeilingHeight() != null && property.getCeilingHeight() != null
            && property.getCeilingHeight().compareTo(profile.getMinCeilingHeight()) < 0)
        score -= 2;

    // ...
    return Math.max(score, 0);
}
```

**Итог аудита:** Интеграция выполнена корректно. Новые параметры `search_profile` прозрачно прокидываются из Flutter Stepper'a в JSON-запрос, мапятся на Java-Entity в Backend'е и напрямую воздействуют на алгоритм `PropertyScoringService`, формируя динамический `totalScore` помещения под конкретные нужды арендатора.
