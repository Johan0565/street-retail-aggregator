package com.example.backend.auth;

import com.example.backend.Security.JwtService;
import com.example.backend.dto.*;
import com.example.backend.entity.*;
import com.example.backend.repository.*;
import com.example.backend.auth.EmailService; // Импортируем наш сервис писем
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Optional;
import java.util.Random;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final TenantProfileRepository tenantProfileRepository;
    private final LandlordProfileRepository landlordProfileRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AuthenticationManager authenticationManager;
    private final EmailService emailService; // Подключаем отправку email

    @Transactional
    public AuthResponse register(RegisterRequest request) {

        // 1. Проверяем email на статус ACTIVE или очищаем старый мусор
        Optional<User> existingUserByEmail = userRepository.findByEmail(request.getEmail());
        if (existingUserByEmail.isPresent()) {
            User user = existingUserByEmail.get();
            if (user.getStatus() == UserStatus.ACTIVE) {
                throw new RuntimeException("Пользователь с таким email уже существует");
            } else {
                // Пользователь не подтвердил почту. Удаляем старую запись.
                userRepository.delete(user);
                userRepository.flush(); // Принудительно применяем удаление в БД прямо сейчас
            }
        }

        // 2. Проверяем ИНН (чтобы не было ошибки 500 при смене почты, но старом ИНН)
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
            Optional<LandlordProfile> existingProfile = landlordProfileRepository.findByInn(request.getInn());
            if (existingProfile.isPresent()) {
                if (existingProfile.get().getUser().getStatus() == UserStatus.ACTIVE) {
                    throw new RuntimeException("Арендодатель с таким ИНН уже зарегистрирован");
                } else {
                    userRepository.delete(existingProfile.get().getUser());
                    userRepository.flush();
                }
            }
        }

        // 3. Создаем нового пользователя
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

        // 4. Создаем профили
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

        // Успешная верификация
        user.setStatus(UserStatus.ACTIVE);
        user.setVerificationCode(null);
        user.setCodeExpiresAt(null);
        userRepository.save(user);

        // Теперь выдаем токен
        String jwtToken = jwtService.generateToken(user);
        return AuthResponse.builder()
                .token(jwtToken)
                .email(user.getEmail())
                .role(user.getRole())
                .message("Успешная авторизация")
                .build();
    }

    @Transactional
    public AuthResponse resendCode(String email) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        if (user.getStatus() == UserStatus.ACTIVE) {
            throw new RuntimeException("Email уже подтвержден");
        }

        // Проверка на Кулдаун: если время истечения еще в будущем, значит 2 минуты не прошло
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

    public AuthResponse login(LoginRequest request) {
        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.getEmail(), request.getPassword())
        );

        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        // Не даем войти, если почта не подтверждена
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
}