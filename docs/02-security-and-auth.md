# 02. Безопасность и аутентификация

Документ описывает подсистему авторизации, регистрации, верификации email и защиты API endpoints в проекте Street Retail Aggregator.

---

## 2.1. Общая схема аутентификации

```
┌─────────────┐                            ┌─────────────────────────────┐
│   Клиент    │                            │         Backend             │
│ (Flutter)   │                            │                             │
└──────┬──────┘                            └──────────────┬──────────────┘
       │                                                  │
       │  POST /api/auth/register                         │
       │  {email, password, role, inn, phone, name}       │
       ├─────────────────────────────────────────────────►│
       │                                                  │ BCryptPasswordEncoder.encode
       │                                                  │ User.status=UNVERIFIED
       │                                                  │ generate 6-digit code
       │                                                  │ EmailService.sendVerificationCode
       │                  AuthResponse(message)           │
       │◄─────────────────────────────────────────────────┤
       │                                                  │
       │  Пользователь получает код по email              │
       │                                                  │
       │  POST /api/auth/verify {email, code}             │
       ├─────────────────────────────────────────────────►│
       │                                                  │ User.status=ACTIVE
       │                                                  │ JwtService.generateToken
       │            AuthResponse(token, email, role)      │
       │◄─────────────────────────────────────────────────┤
       │                                                  │
       │  GET /api/properties/recommended                 │
       │  Authorization: Bearer <token>                   │
       ├─────────────────────────────────────────────────►│
       │                                                  │ JwtAuthenticationFilter
       │                                                  │ │ extractUsername
       │                                                  │ │ UserDetailsService.loadUserByUsername
       │                                                  │ │ isTokenValid (signature+expiry)
       │                                                  │ │ SecurityContext.set(authToken)
       │                                                  │ ▼
       │                                                  │ Controller @PreAuthorize / role check
       │                  List<Property>                  │
       │◄─────────────────────────────────────────────────┤
```

**Ключевые свойства схемы:**

- **Stateless** — нет HTTP-сессий, нет cookies, нет server-side state. Авторизация на каждый запрос через `Authorization: Bearer <JWT>`.
- **Двухфазная регистрация** — `register` создаёт пользователя со статусом `UNVERIFIED`, JWT не выдаётся; `verify` подтверждает код из email и только тогда возвращает JWT.
- **JWT 24 часа без refresh-токена.** После истечения нужен повторный логин. Для UX это компенсируется мульти-аккаунтным хранилищем во Flutter (`AuthService.getSavedAccounts`).
- **Локальная аутентификация** — нет OAuth/SSO, всё через email+пароль.

---

## 2.2. `SecurityConfig` — фильтр-чейн и правила доступа

[`SecurityConfig.java`](../backend/src/main/java/com/example/backend/Security/SecurityConfig.java)

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthFilter;
    private final AuthenticationProvider authenticationProvider; // Берется из ApplicationConfig

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .cors(cors -> cors.configurationSource(request -> {
                    var config = new CorsConfiguration();
                    config.setAllowedOriginPatterns(List.of("*"));
                    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
                    config.setAllowedHeaders(List.of("*"));
                    return config;
                }))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/auth/**").permitAll()
                        .requestMatchers("/api/properties/{id}").permitAll()
                        .requestMatchers("/api/categories/**").permitAll()
                        .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                        .requestMatchers("/error").permitAll()
                        .requestMatchers("/ws/**").permitAll()
                        .requestMatchers("/uploads/**").permitAll()
                        .anyRequest().authenticated()
                )
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                )
                .authenticationProvider(authenticationProvider)
                .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}
```

### 2.2.1. CSRF

`csrf().disable()` — корректно для **stateless JWT API**. CSRF-атаки эксплуатируют автоматическую отправку cookies браузером; у нас нет cookies, токен передаётся явным заголовком `Authorization`, который браузер не подставит автоматически из-за CORS.

### 2.2.2. CORS

Открытый CORS:

```java
config.setAllowedOriginPatterns(List.of("*"));
config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
config.setAllowedHeaders(List.of("*"));
```

Это допустимо, потому что:
- Real-time клиент — Flutter APK (не браузер, на CORS не смотрит).
- Браузерные клиенты используются только для Swagger UI (того же origin).

Для production-окружения с веб-фронтом стоит сузить `allowedOriginPatterns` до конкретных доменов.

### 2.2.3. Публичные endpoint'ы

| Путь                                       | Зачем публичный                                                                 |
|--------------------------------------------|---------------------------------------------------------------------------------|
| `/api/auth/**`                             | Регистрация, логин, верификация — токена ещё нет                                |
| `/api/properties/{id}`                     | Детальная карточка помещения — открытый просмотр без логина                     |
| `/api/categories/**`                       | Справочник категорий бизнеса — публичный read-only                              |
| `/v3/api-docs/**`, `/swagger-ui/**`        | OpenAPI-доки                                                                    |
| `/error`                                   | Spring error-страница                                                           |
| `/ws/**`                                   | STOMP WebSocket endpoint (аутентификация на уровне STOMP-фреймов, не HTTP)      |
| `/uploads/**`                              | Картинки помещений и аватары — публичная раздача через `WebMvcConfig`           |

Всё остальное — `.anyRequest().authenticated()`, то есть требует валидный JWT.

**Тонкость с `/api/properties/{id}`.** Только эта конкретная форма публична. `/api/properties` (список рекомендованных), `/api/properties/{id}/score` и mutate-операции (`POST/PUT/DELETE`) — требуют аутентификации.

### 2.2.4. STATELESS-сессии

```java
.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
```

Spring Security не создаёт `HttpSession`, не выставляет `JSESSIONID`-cookie. Каждый запрос рассматривается независимо: `SecurityContext` заполняется фильтром `JwtAuthenticationFilter` из JWT в заголовке и обнуляется после ответа.

### 2.2.5. `@EnableMethodSecurity`

Включает аннотации `@PreAuthorize`, `@PostAuthorize`, `@Secured` на уровне методов. В текущей кодовой базе они используются в контроллерах для проверки роли:

```java
// в контроллерах: проверки по @AuthenticationPrincipal + явная проверка role
```

Подавляющая часть ownership-проверок (например, «эта заявка моя?») делается явно в сервисах (см. §4 «Сервисы», `ApplicationService.deleteApplication`).

---

## 2.3. `ApplicationConfig` — `UserDetailsService` и `PasswordEncoder`

[`ApplicationConfig.java`](../backend/src/main/java/com/example/backend/Security/ApplicationConfig.java)

```java
@Configuration
@RequiredArgsConstructor
public class ApplicationConfig {

    private final UserRepository userRepository;

    @Bean
    public UserDetailsService userDetailsService() {
        return username -> userRepository.findByEmail(username)
                .orElseThrow(() -> new UsernameNotFoundException("Пользователь не найден"));
    }

    @Bean
    public AuthenticationProvider authenticationProvider() {
        DaoAuthenticationProvider authProvider = new DaoAuthenticationProvider(userDetailsService());
        authProvider.setPasswordEncoder(passwordEncoder());
        return authProvider;
    }

    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration config) throws Exception {
        return config.getAuthenticationManager();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
```

### 2.3.1. `UserDetailsService`

Lookup по email (см. `User.getUsername()` возвращает email). Возвращает сам `User` — сущность реализует `UserDetails` (см. §2.5).

### 2.3.2. `AuthenticationProvider`

`DaoAuthenticationProvider` использует:
- `UserDetailsService` → найти пользователя по email
- `PasswordEncoder` → сравнить хэш пароля

В `AuthService.login` мы явно дергаем `AuthenticationManager.authenticate(new UsernamePasswordAuthenticationToken(email, password))`, что под капотом и проходит через этот provider.

### 2.3.3. `BCryptPasswordEncoder`

- BCrypt с default cost factor = 10 (≈100мс per hash).
- Соль автогенерируется и хранится внутри строки хэша.
- При `register` мы делаем `passwordEncoder.encode(rawPassword)`; при `login` Spring Security сам вызывает `matches(raw, hash)`.

---

## 2.4. JWT: `JwtService`

[`JwtService.java`](../backend/src/main/java/com/example/backend/Security/JwtService.java)

```java
@Service
public class JwtService {

    @Value("${jwt.secret:404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970}")
    private String secretKey;

    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }

    public boolean isTokenValid(String token, UserDetails userDetails) {
        final String username = extractUsername(token);
        return (username.equals(userDetails.getUsername())) && !isTokenExpired(token);
    }

    private boolean isTokenExpired(String token) {
        return extractExpiration(token).before(new Date());
    }

    private Claims extractAllClaims(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(getSignInKey())
                .build()
                .parseClaimsJws(token)
                .getBody();
    }

    private Key getSignInKey() {
        byte[] keyBytes = Decoders.BASE64.decode(secretKey);
        return Keys.hmacShaKeyFor(keyBytes);
    }

    public String generateToken(UserDetails userDetails) {
        return Jwts.builder()
                .setSubject(userDetails.getUsername())
                .setIssuedAt(new Date(System.currentTimeMillis()))
                .setExpiration(new Date(System.currentTimeMillis() + 1000 * 60 * 60 * 24)) // 24h
                .signWith(getSignInKey(), SignatureAlgorithm.HS256)
                .compact();
    }
}
```

### 2.4.1. Алгоритм и ключ

- **HS256** — HMAC-SHA256. Симметричный: один и тот же ключ для подписи и верификации.
- **Ключ — Base64-decoded `jwt.secret`.** Дефолт зашит в коде (`404E63526655...`), пригоден для разработки; для production обязательно переопределить через переменную окружения.
- **Минимальная длина ключа после декодирования** должна быть ≥256 бит (32 байта) — `Keys.hmacShaKeyFor` проверит это и кинет `WeakKeyException`, если ключ короче.

### 2.4.2. Структура токена

JWT-payload (Claims):

```json
{
  "sub": "user@example.com",
  "iat": 1735000000,
  "exp": 1735086400
}
```

- `sub` (Subject) — email. Custom claims (роли, id) **не добавляются** — все атрибуты читаются из БД на каждый запрос через `UserDetailsService`. Это означает: смена роли пользователя в БД мгновенно отражается на правах (нет «протухшего ROLE_TENANT в токене»).
- `iat`, `exp` — стандартные NumericDate.
- **TTL = 24 часа** (`1000 * 60 * 60 * 24`).

### 2.4.3. Валидация

```java
public boolean isTokenValid(String token, UserDetails userDetails) {
    final String username = extractUsername(token);
    return (username.equals(userDetails.getUsername())) && !isTokenExpired(token);
}
```

Проверяет:
1. Подпись валидна (внутри `extractAllClaims` через `parseClaimsJws`).
2. `sub` совпадает с найденным в БД email'ом.
3. Не истёк.

Изначальная подпись валидируется в `parseClaimsJws` — если кто-то подменит хоть один символ, `JwtException` улетает наверх и фильтр не выставит `SecurityContext`.

---

## 2.5. `User` как `UserDetails`

[`User.java`](../backend/src/main/java/com/example/backend/entity/User.java)

Сущность напрямую реализует `UserDetails`, чтобы не плодить адаптеры:

```java
@Entity
@Table(name = "users")
public class User implements UserDetails {

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

    @Override
    @JsonIgnore
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + role.name()));
    }

    @Override
    public String getUsername() { return email; }

    @Override
    @JsonIgnore
    public String getPassword() { return passwordHash; }

    @Override
    @JsonIgnore
    public boolean isAccountNonExpired() { return true; }
    @Override
    @JsonIgnore
    public boolean isAccountNonLocked() { return status != UserStatus.BANNED; }
    @Override
    @JsonIgnore
    public boolean isCredentialsNonExpired() { return true; }
    @Override
    @JsonIgnore
    public boolean isEnabled() { return status == UserStatus.ACTIVE; }
}
```

### 2.5.1. Маппинг ролей

- В БД `role` хранится как enum-string: `TENANT`, `LANDLORD`, `ADMIN` (см. [`Role.java`](../backend/src/main/java/com/example/backend/entity/enums/Role.java)).
- В `GrantedAuthority` отдаётся с префиксом `ROLE_` — это обязательный формат для `hasRole('TENANT')` в `@PreAuthorize`. Spring Security сам добавляет/убирает префикс, и без него аннотации не работают.

### 2.5.2. Статусы пользователя

[`UserStatus.java`](../backend/src/main/java/com/example/backend/entity/enums/UserStatus.java):

```java
public enum UserStatus {
    UNVERIFIED, ACTIVE, BANNED
}
```

- `UNVERIFIED` → `isEnabled() = false` → Spring Security возвращает `DisabledException` при попытке логина. Дополнительная явная проверка есть в `AuthService.login` (`"Пожалуйста, подтвердите вашу электронную почту"`).
- `ACTIVE` → нормальное состояние, доступ есть.
- `BANNED` → `isAccountNonLocked() = false` → `LockedException`. На текущем этапе нет UI-логики банов, оставлено как задел.

### 2.5.3. JsonIgnore

Все чувствительные/heavy-поля помечены `@JsonIgnore`, чтобы при сериализации `User` в ответ контроллера не утекли:
- `passwordHash`
- `verificationCode`, `codeExpiresAt`
- `createdAt`
- `tenantProfile`, `landlordProfile` (lazy associations)
- `favoriteProperties` (lazy ManyToMany)
- все UserDetails-методы (`getAuthorities`, `getPassword`, `isAccountNonExpired`, ...)

Это критично, потому что в нескольких местах `User` возвращается прямо (без явного DTO), и без `@JsonIgnore` Hibernate-проксирование вызвало бы `LazyInitializationException` или утечку хэша пароля.

---

## 2.6. `JwtAuthenticationFilter` — извлечение токена из запроса

[`JwtAuthenticationFilter.java`](../backend/src/main/java/com/example/backend/Security/JwtAuthenticationFilter.java)

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain
    ) throws ServletException, IOException {

        final String authHeader = request.getHeader("Authorization");
        final String jwt;
        final String userEmail;

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        jwt = authHeader.substring(7);
        userEmail = jwtService.extractUsername(jwt);

        if (userEmail != null && SecurityContextHolder.getContext().getAuthentication() == null) {
            UserDetails userDetails = this.userDetailsService.loadUserByUsername(userEmail);

            if (jwtService.isTokenValid(jwt, userDetails)) {
                UsernamePasswordAuthenticationToken authToken = new UsernamePasswordAuthenticationToken(
                        userDetails,
                        null,
                        userDetails.getAuthorities()
                );
                authToken.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authToken);
            }
        }

        filterChain.doFilter(request, response);
    }
}
```

### Поведение

1. `OncePerRequestFilter` — Spring гарантирует ровно один вызов на запрос (важно при internal forwards).
2. **Нет `Authorization: Bearer ...`** → просто пропускает дальше. Если endpoint публичный — пройдёт; если защищённый — `.anyRequest().authenticated()` вернёт 403.
3. **Есть токен:**
   - Извлекает email (`sub`) из payload **без проверки подписи** на этом этапе — `extractUsername` сделает `parseClaimsJws`, которое и проверит подпись; если подпись битая, бросит `SignatureException` → 500. (В production стоило бы обернуть в try/catch и возвращать 401.)
   - Если в `SecurityContext` уже есть аутентификация (например, после другого фильтра) — не перетирает.
   - Загружает `UserDetails` из БД через `UserDetailsService` — **на каждый запрос новый JPA-lookup**. Это даёт актуальные роли/статус, но добавляет 1 SELECT на каждый защищённый запрос.
   - `isTokenValid` сверяет email и проверяет expiry.
   - Создаёт `UsernamePasswordAuthenticationToken` без credentials (пароль не нужен — токен уже валидирован), с authorities из `UserDetails.getAuthorities()`.
   - Кладёт в `SecurityContextHolder`. С этой точки `@AuthenticationPrincipal User user` в контроллерах работает.

### Регистрация фильтра

В `SecurityConfig`:

```java
.addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class);
```

Ставится **перед** дефолтным `UsernamePasswordAuthenticationFilter` (который обрабатывает form-login на `/login`, у нас отключён). Так `SecurityContext` уже заполнен к моменту, когда Spring проверяет `.anyRequest().authenticated()`.

---

## 2.7. `AuthController` — endpoints

[`AuthController.java`](../backend/src/main/java/com/example/backend/auth/AuthController.java)

```java
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@RequestBody RegisterRequest request) {
        return ResponseEntity.ok(authService.register(request));
    }

    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@RequestBody LoginRequest request) {
        return ResponseEntity.ok(authService.login(request));
    }

    @PostMapping("/verify")
    public ResponseEntity<AuthResponse> verify(@RequestBody VerifyEmailRequest request) {
        return ResponseEntity.ok(authService.verifyEmail(request));
    }

    @PostMapping("/resend-code")
    public ResponseEntity<AuthResponse> resendCode(@RequestParam String email) {
        return ResponseEntity.ok(authService.resendCode(email));
    }
}
```

### 2.7.1. Эндпоинты

| Метод | Путь                       | Тело                                                          | Что возвращает                              |
|-------|----------------------------|---------------------------------------------------------------|---------------------------------------------|
| POST  | `/api/auth/register`       | `RegisterRequest{email, password, role, name, inn, phone}`    | `AuthResponse{message}` (без токена)        |
| POST  | `/api/auth/verify`         | `VerifyEmailRequest{email, code}`                             | `AuthResponse{token, email, role, message}` |
| POST  | `/api/auth/login`          | `LoginRequest{email, password}`                               | `AuthResponse{token, email, role, message}` |
| POST  | `/api/auth/resend-code`    | `?email=` (query)                                             | `AuthResponse{message}`                     |

### 2.7.2. DTO

[`RegisterRequest.java`](../backend/src/main/java/com/example/backend/dto/RegisterRequest.java):

```java
@Data @Builder
public class RegisterRequest {
    private String email;
    private String password;
    private Role role;     // TENANT или LANDLORD
    private String name;   // ФИО или название компании
    private String inn;
    private String phone;
}
```

[`AuthResponse.java`](../backend/src/main/java/com/example/backend/dto/AuthResponse.java):

```java
@Data @Builder
public class AuthResponse {
    private String token;
    private String email;
    private Role role;
    private String message;
}
```

[`VerifyEmailRequest.java`](../backend/src/main/java/com/example/backend/dto/VerifyEmailRequest.java):

```java
@Data
public class VerifyEmailRequest {
    private String email;
    private String code;
}
```

---

## 2.8. `AuthService` — бизнес-логика

[`AuthService.java`](../backend/src/main/java/com/example/backend/auth/AuthService.java)

### 2.8.1. `register(RegisterRequest)` — 5 шагов

```java
@Transactional
public AuthResponse register(RegisterRequest request) {
    // 1. Проверяем email на статус ACTIVE или очищаем старый мусор
    Optional<User> existingUserByEmail = userRepository.findByEmail(request.getEmail());
    if (existingUserByEmail.isPresent()) {
        User user = existingUserByEmail.get();
        if (user.getStatus() == UserStatus.ACTIVE) {
            throw new RuntimeException("Пользователь с таким email уже существует");
        } else {
            userRepository.delete(user);
            userRepository.flush();
        }
    }

    // 2. Проверяем ИНН
    if (request.getRole() == Role.TENANT) {
        Optional<TenantProfile> existingProfile = tenantProfileRepository.findByInn(request.getInn());
        if (existingProfile.isPresent()) {
            if (existingProfile.get().getUser().getStatus() == UserStatus.ACTIVE) {
                throw new RuntimeException("Арендатор с таким ИНН уже зарегистрирован");
            } else {
                userRepository.delete(existingProfile.get().getUser());
                userRepository.flush();
            }
        }
    } else if (request.getRole() == Role.LANDLORD) {
        // симметрично для landlord_profiles.inn
    }

    // 3. Создаем пользователя со статусом UNVERIFIED и 6-значным кодом
    String code = String.format("%06d", new Random().nextInt(1000000));

    User user = User.builder()
            .email(request.getEmail())
            .passwordHash(passwordEncoder.encode(request.getPassword()))
            .role(request.getRole())
            .status(UserStatus.UNVERIFIED)
            .verificationCode(code)
            .codeExpiresAt(LocalDateTime.now().plusMinutes(2))
            .build();

    User savedUser = userRepository.save(user);

    // 4. Создаем профиль TenantProfile или LandlordProfile
    if (request.getRole() == Role.TENANT) {
        TenantProfile tenantProfile = TenantProfile.builder()
                .user(savedUser)
                .name(request.getName())
                .inn(request.getInn())
                .phone(request.getPhone())
                .build();
        tenantProfileRepository.save(tenantProfile);
    } else if (request.getRole() == Role.LANDLORD) {
        LandlordProfile landlordProfile = LandlordProfile.builder()
                .user(savedUser)
                .companyName(request.getName())
                .inn(request.getInn())
                .phone(request.getPhone())
                .isVerified(false)
                .build();
        landlordProfileRepository.save(landlordProfile);
    }

    // 5. Отправляем письмо
    emailService.sendVerificationCode(savedUser.getEmail(), code);

    return AuthResponse.builder()
            .message("Код подтверждения отправлен на вашу почту.")
            .build();
}
```

**Ключевые свойства:**

1. **«Очистка мусора» при дубликате email/ИНН в статусе `UNVERIFIED`.** Если пользователь начал регистрацию, ввёл код неправильно (или не успел), и пробует заново — старая запись удаляется. Это позволяет «переиграть» регистрацию с тем же email. `userRepository.flush()` принудительно применяет DELETE до того, как мы попытаемся INSERT с тем же UNIQUE email — иначе constraint violation.
2. **Уникальность по email (`users.email`) и по ИНН (`tenant_profiles.inn` / `landlord_profiles.inn`)** — проверяется отдельно, потому что разные таблицы. ИНН для `LandlordProfile` без `@Column(unique=true)` — но в коде проверка есть.
3. **6-значный код** — `String.format("%06d", new Random().nextInt(1000000))`. Использует `Random`, не `SecureRandom`. Для production стоит SecureRandom — текущий `Random` предсказуем на 2^48 циклах, но при TTL 2 минуты атака непрактична.
4. **TTL кода — 2 минуты.** Хранится в `User.codeExpiresAt`.
5. **JWT не выдаётся** — после `register` пользователь обязан подтвердить email через `/verify`.
6. **`@Transactional`** — вся регистрация атомарна: либо создались user + profile, либо ничего.

### 2.8.2. `verifyEmail(VerifyEmailRequest)`

```java
@Transactional
public AuthResponse verifyEmail(VerifyEmailRequest request) {
    User user = userRepository.findByEmail(request.getEmail())
            .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

    if (user.getStatus() == UserStatus.ACTIVE) {
        throw new RuntimeException("Email уже подтвержден");
    }
    if (user.getCodeExpiresAt().isBefore(LocalDateTime.now())) {
        throw new RuntimeException("Код истек. Запросите новый.");
    }
    if (!user.getVerificationCode().equals(request.getCode())) {
        throw new RuntimeException("Неверный код");
    }

    user.setStatus(UserStatus.ACTIVE);
    user.setVerificationCode(null);
    user.setCodeExpiresAt(null);
    userRepository.save(user);

    String jwtToken = jwtService.generateToken(user);
    return AuthResponse.builder()
            .token(jwtToken)
            .email(user.getEmail())
            .role(user.getRole())
            .message("Успешная авторизация")
            .build();
}
```

**Что важно:**

- Сравнение кода — простой `equals`. Timing-attack здесь не критична: 6 цифр и TTL 2 минуты дают ~10^6 / 120s = 8333 попытки в секунду нужно, чтобы перебрать за один TTL — не реалистично через сетевой POST.
- После успеха `verificationCode` и `codeExpiresAt` зануляются — нельзя использовать тот же код повторно.
- Выдаётся полноценный JWT — пользователь сразу залогинен.

### 2.8.3. `resendCode(email)` — анти-флуд

```java
@Transactional
public AuthResponse resendCode(String email) {
    User user = userRepository.findByEmail(email)
            .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

    if (user.getStatus() == UserStatus.ACTIVE) {
        throw new RuntimeException("Email уже подтвержден");
    }

    // Кулдаун: если время истечения предыдущего кода ещё в будущем, 2 минуты не прошло
    if (user.getCodeExpiresAt() != null && user.getCodeExpiresAt().isAfter(LocalDateTime.now())) {
        throw new RuntimeException("Вы можете запросить новый код только через 2 минуты");
    }

    String newCode = String.format("%06d", new Random().nextInt(1000000));
    user.setVerificationCode(newCode);
    user.setCodeExpiresAt(LocalDateTime.now().plusMinutes(2));
    userRepository.save(user);

    emailService.sendVerificationCode(user.getEmail(), newCode);
    return AuthResponse.builder().message("Новый код отправлен").build();
}
```

**Антифлуд** реализован через `codeExpiresAt`: новый код можно запросить только когда предыдущий уже истёк (т.е. не чаще раза в 2 минуты). Это защищает от спама на чужой email.

### 2.8.4. `login(LoginRequest)`

```java
public AuthResponse login(LoginRequest request) {
    authenticationManager.authenticate(
            new UsernamePasswordAuthenticationToken(request.getEmail(), request.getPassword())
    );

    User user = userRepository.findByEmail(request.getEmail())
            .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

    if (user.getStatus() == UserStatus.UNVERIFIED) {
        throw new RuntimeException("Пожалуйста, подтвердите вашу электронную почту");
    }

    String jwtToken = jwtService.generateToken(user);
    return AuthResponse.builder()
            .token(jwtToken)
            .email(user.getEmail())
            .role(user.getRole())
            .message("Успешная авторизация")
            .build();
}
```

**Поток:**

1. `authenticationManager.authenticate(...)` — внутри идёт через `DaoAuthenticationProvider`: `UserDetailsService` находит пользователя, `BCryptPasswordEncoder.matches(raw, hash)` проверяет пароль. При неверном пароле — `BadCredentialsException`.
2. Дополнительная явная проверка статуса (хотя Spring Security сам бы её сделал через `isEnabled()` — здесь это дублирующее сообщение для UX).
3. Генерируется новый JWT (старый не отзывается — у нас нет блэклиста, отзыв до истечения TTL невозможен).

---

## 2.9. `EmailService` — отправка кода верификации

[`EmailService.java`](../backend/src/main/java/com/example/backend/auth/EmailService.java)

```java
@Service
@RequiredArgsConstructor
public class EmailService {

    private final JavaMailSender mailSender;

    @Value("${spring.mail.username}")
    private String fromEmail;

    public void sendVerificationCode(String to, String code) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(fromEmail);
        message.setTo(to);
        message.setSubject("Код подтверждения | Street Retail Aggregator");
        message.setText("Ваш код подтверждения: " + code + "\n\nКод действителен в течение 2 минут.");

        mailSender.send(message);
    }
}
```

- Использует `JavaMailSender`, который Spring настраивает из `spring.mail.*` properties.
- В качестве from — `spring.mail.username` (это адрес Gmail-аккаунта; пароль — App Password, не основной пароль Gmail).
- `SimpleMailMessage` — plain-text. HTML/branding можно добавить, но для 6-значного кода это избыточно.

**Failure mode.** При сбое SMTP `mailSender.send` бросит `MailException`, что прокатится наверх и поломает `register`. Сейчас обработки нет — пользователь увидит RuntimeException. В production стоит retry + асинхронная очередь.

---

## 2.10. Swagger / OpenAPI

[`SwaggerConfig.java`](../backend/src/main/java/com/example/backend/auth/SwaggerConfig.java)

```java
@Configuration
public class SwaggerConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        final String securitySchemeName = "bearerAuth";

        return new OpenAPI()
                .info(new Info()
                        .title("Street Retail Aggregator API")
                        .version("1.0")
                        .description("Документация REST API для курсового проекта"))
                .addSecurityItem(new SecurityRequirement().addList(securitySchemeName))
                .components(new Components()
                        .addSecuritySchemes(securitySchemeName, new SecurityScheme()
                                .name(securitySchemeName)
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")
                                .description("Введите JWT токен, полученный при логине или регистрации.")));
    }
}
```

- Swagger UI доступен на `/swagger-ui.html`, OpenAPI 3.0 JSON — на `/v3/api-docs`.
- Кнопка `Authorize` в UI принимает Bearer JWT — после вставки токена все запросы из UI автоматически отправляются с `Authorization` header.
- Сами endpoints `/swagger-ui/**` и `/v3/api-docs/**` помечены `permitAll()` в `SecurityConfig`.

---

## 2.11. Поток данных при защищённом запросе

Пример: тенант открывает рекомендованные помещения.

```
GET /api/properties/recommended
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9...
```

```
1. Tomcat принимает запрос.

2. Spring SecurityFilterChain:
   ├─ DisableEncodeUrlFilter
   ├─ WebAsyncManagerIntegrationFilter
   ├─ SecurityContextHolderFilter
   ├─ ...
   ├─ JwtAuthenticationFilter ◄── наш фильтр
   │     ├─ Извлекает "Bearer ..." → "eyJ..."
   │     ├─ jwtService.extractUsername → "user@example.com"
   │     ├─ userDetailsService.loadUserByUsername → SELECT * FROM users WHERE email='user@example.com'
   │     │  └─ User со status=ACTIVE, role=TENANT
   │     ├─ jwtService.isTokenValid(token, user) → true
   │     └─ SecurityContextHolder.setAuthentication(new UsernamePasswordAuthenticationToken(user, null, [ROLE_TENANT]))
   ├─ UsernamePasswordAuthenticationFilter (skip — нет login form-data)
   ├─ ...
   ├─ AuthorizationFilter
   │     └─ Проверяет .anyRequest().authenticated() → OK, есть аутентификация
   └─ DispatcherServlet

3. PropertyController.getRecommendedProperties:
      └─ @AuthenticationPrincipal User user — берёт из SecurityContextHolder
      └─ propertyService.getRecommendedPropertiesForTenant(user.getId())

4. Сервис возвращает List<Property>, Jackson сериализует в JSON.

5. SecurityContextHolder.clearContext() — после ответа.
```

При невалидном/истёкшем токене:
- `JwtAuthenticationFilter` не выставляет аутентификацию.
- `AuthorizationFilter` видит `.anyRequest().authenticated()` без auth → бросает `AccessDeniedException`.
- `AccessDeniedHandler` отдаёт **403 Forbidden** (не 401 — это особенность Spring Security 6 по умолчанию).

---

## 2.12. Точки ответственности (cheat-sheet)

| Артефакт                       | Ответственность                                                          |
|--------------------------------|--------------------------------------------------------------------------|
| `SecurityConfig`               | Список публичных/защищённых путей, CSRF/CORS, регистрация фильтра        |
| `ApplicationConfig`            | `UserDetailsService`, `PasswordEncoder`, `AuthenticationProvider`        |
| `JwtService`                   | Подпись, парсинг, проверка expiry JWT                                    |
| `JwtAuthenticationFilter`      | Чтение `Authorization` header, выставление `SecurityContext`             |
| `User implements UserDetails`  | Маппинг роли в `ROLE_*` authority, статус → enabled/locked               |
| `AuthController`               | HTTP-endpoints `/api/auth/**`                                            |
| `AuthService`                  | Логика регистрации, верификации, логина, ресенда                         |
| `EmailService`                 | Отправка 6-значного кода по SMTP                                         |
| `SwaggerConfig`                | OpenAPI 3 спека с Bearer-схемой                                          |

---

## 2.13. Известные слабые места

1. **Дефолтный `jwt.secret` в коде** — обязательно переопределять в production.
2. **Нет refresh-token** — после 24ч пользователь должен повторно логиниться.
3. **Нет blacklist'a JWT** — украденный токен валиден до естественного истечения.
4. **`Random` вместо `SecureRandom`** для 6-значного кода. На текущем масштабе атаки безопасно, но стоит исправить.
5. **`UserDetailsService` бьёт в БД на каждый запрос.** Возможный кэш на 1–5 минут существенно ускорил бы hot path, но усложнил бы инвалидацию при бане/смене роли.
6. **CORS открыт `*`.** Подойдёт для нативного клиента, для веб-фронта нужно сузить.
7. **`MailException` не обработан** — упавший SMTP роняет `register`. Стоит асинхронная очередь / retry.
8. **`@PreAuthorize` используется редко** — большинство ownership-проверок «вручную» в сервисах. Это работает, но менее декларативно.
