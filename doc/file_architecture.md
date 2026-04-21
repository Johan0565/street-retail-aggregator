# Архитектура проекта "Street Retail Aggregator"

Проект разделен на две основные части: **Backend** (серверная часть) и **Frontend** (мобильное/веб-приложение). Ниже приведено подробное описание файловой архитектуры обоих компонентов.

---

## 1. Backend

Серверная часть реализована на языке Java с использованием фреймворка Spring Boot. Проект имеет стандартную для Spring Boot структуру пакетов с разделением на слои (многослойная архитектура).

### Структура директорий `backend/src/main/java/com/example/backend`

*   **`BackendApplication.java`**
    *   Главный класс, содержащий метод `main` и являющийся точкой входа в приложение (запуск Spring Boot).
*   **`auth/`** (Пакет авторизации и конфигурации)
    *   Содержит логику для работы с аутентификацией и базовыми сервисами.
    *   Включает: `AuthController.java` (контроллер для входа и регистрации), `AuthService.java` (логика авторизации), `EmailService.java` (отправка писем) и `SwaggerConfig.java` (конфигурация документации API).
*   **`controller/`** (Слой контроллеров / REST API)
    *   Отвечает за обработку входящих HTTP-запросов от клиента и возврат ответов. Контроллеры делегируют бизнес-логику в сервисный слой.
    *   Включает контроллеры: `ApplicationController.java`, `CategoryController.java`, `FavoriteController.java`, `ProfileController.java`, `PropertyController.java`.
*   **`dto/`** (Data Transfer Objects)
    *   Объекты передачи данных, используемые для обмена информацией между клиентом и сервером. Обеспечивают изоляцию внутренних сущностей БД от внешнего API.
    *   Содержит объекты для запросов (Request) и ответов (Response), например: `LoginRequest`, `CreatePropertyRequest`, `ApplicationResponseDto` и др.
*   **`entity/`** (Слой сущностей БД)
    *   Модели предметной области (JPA Entities), которые маппятся на таблицы в реляционной базе данных.
    *   Включает основные сущности: `User.java`, `Property.java`, `Application.java`, `TenantProfile.java`, `LandlordProfile.java` и др.
    *   **`enums/`**: Вложенный пакет с перечислениями, определяющими фиксированные наборы значений (например: `Role`, `DealType`, `PropertyStatus`, `ApplicationStatus`).
*   **`repository/`** (Слой доступа к данным)
    *   Интерфейсы репозиториев (наследуют Spring Data JPA), обеспечивающие выполнение CRUD-операций и формирование SQL-запросов к базе данных для соответствующих сущностей (например, `PropertyRepository.java`).
*   **`Security/`** (Слой безопасности)
    *   Классы конфигурации и фильтры для обеспечения безопасности (Spring Security).
    *   Включает логику обработки JWT токенов: `SecurityConfig.java`, `JwtAuthenticationFilter.java`, `JwtService.java`.
*   **`service/`** (Слой бизнес-логики)
    *   Содержит основную бизнес-логику приложения. Сервисы вызываются контроллерами, обрабатывают данные и взаимодействуют с репозиториями.
    *   Включает: `ApplicationService.java`, `PropertyService.java`, `ProfileService.java` и др.

---

## 2. Frontend

Клиентская часть реализована на фреймворке Flutter (язык Dart). Архитектура приложения строится по принципам Clean Architecture / Feature-Based с разделением на смысловые слои и роли.

### Структура директорий `frontend/lib`

*   **`main.dart`**
    *   Точка входа во Flutter-приложение. Инициализирует приложение, настраивает роутинг и тему.

### Пакет `src/` (Основной исходный код)

*   **`domain/`** (Модели данных)
    *   Слой предметной области клиента. Содержит Dart-классы, описывающие сущности, получаемые от backend API.
    *   Файлы: `property.dart`, `application_model.dart`, `user_profile.dart`, `business_category.dart`.
*   **`presentation/`** (Слой представления / UI)
    *   Содержит все экраны, виджеты и логику отрисовки интерфейса. Для удобства навигации и поддержки экраны (screens) разделены по ролям пользователей:
        *   **`auth/`**: Экраны аутентификации (`login_screen.dart`, `register_screen.dart`).
        *   **`landlord/`**: Экраны для роли "Арендодатель". Управление своими объектами недвижимости (`my_properties_screen.dart`, `add_property_screen.dart`, `map_picker_screen.dart`) и заявками (`incoming_applications_screen.dart`).
        *   **`tenant/`**: Экраны для роли "Арендатор". Поиск объектов на карте (`map_screen.dart`), просмотр деталей (`property_details_screen.dart`), управление профилем, избранным и своими заявками.
*   **`services/`** (Слой сервисов / API Client)
    *   Классы для взаимодействия с Backend API через HTTP (REST). Отвечают за отправку запросов, парсинг JSON-ответов и обработку ошибок.
    *   Файлы: `auth_service.dart`, `property_service.dart`, `application_service.dart`, `favorite_service.dart`, `category_service.dart`.
