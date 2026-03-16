package com.example.backend.auth;
import com.example.backend.Security.JwtService;
import com.example.backend.dto.AuthResponse;
import com.example.backend.dto.LoginRequest;
import com.example.backend.dto.RegisterRequest;
import com.example.backend.entity.*;
import com.example.backend.repository.LandlordProfileRepository;
import com.example.backend.repository.TenantProfileRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final TenantProfileRepository tenantProfileRepository;
    private final LandlordProfileRepository landlordProfileRepository;

    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AuthenticationManager authenticationManager;

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        // Проверка на существующий email
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("Пользователь с таким email уже существует");
        }

        // Создаем базового пользователя
        User user = User.builder()
                .email(request.getEmail())
                .passwordHash(passwordEncoder.encode(request.getPassword()))
                .role(request.getRole())
                .status(UserStatus.ACTIVE)
                .build();

        // Сохраняем пользователя (получаем ID из базы)
        User savedUser = userRepository.save(user);

        // В зависимости от роли создаем соответствующий профиль
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
                    .isVerified(false) // По умолчанию арендодатель не верифицирован
                    .build();
            landlordProfileRepository.save(landlordProfile);
        }

        // Генерируем токен для нового пользователя
        String jwtToken = jwtService.generateToken(savedUser);

        return AuthResponse.builder()
                .token(jwtToken)
                .email(savedUser.getEmail())
                .role(savedUser.getRole())
                .build();
    }

    public AuthResponse login(LoginRequest request) {
        // Делегируем проверку пароля стандартному AuthenticationManager из Spring Security
        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                        request.getEmail(),
                        request.getPassword()
                )
        );

        // Если дошли сюда, значит пароль верный. Ищем пользователя в базе
        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        // Генерируем токен
        String jwtToken = jwtService.generateToken(user);

        return AuthResponse.builder()
                .token(jwtToken)
                .email(user.getEmail())
                .role(user.getRole())
                .build();
    }
}