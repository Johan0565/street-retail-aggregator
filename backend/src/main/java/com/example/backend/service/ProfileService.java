package com.example.backend.service;

import com.example.backend.dto.UpdateLandlordProfileRequest;
import com.example.backend.dto.UpdateTenantProfileRequest;
import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.LandlordProfile;
import com.example.backend.entity.TenantProfile;
import com.example.backend.entity.User;
import com.example.backend.repository.BusinessCategoryRepository;
import com.example.backend.repository.LandlordProfileRepository;
import com.example.backend.repository.TenantProfileRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
@RequiredArgsConstructor
public class ProfileService {

    private final TenantProfileRepository tenantProfileRepository;
    private final LandlordProfileRepository landlordProfileRepository;
    private final BusinessCategoryRepository businessCategoryRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;

    // --- ЛОГИКА АРЕНДАТОРА (TENANT) ---

    @Transactional(readOnly = true)
    public TenantProfile getTenantProfile(Long userId) {
        TenantProfile profile = tenantProfileRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Профиль арендатора не найден"));
        userRepository.findById(userId).ifPresent(u -> profile.setAvatarUrl(u.getAvatarUrl()));
        return profile;
    }

    @Transactional
    public TenantProfile updateTenantProfile(Long userId, UpdateTenantProfileRequest request) {
        TenantProfile profile = getTenantProfile(userId);

        profile.setName(request.getName());
        profile.setInn(request.getInn());
        profile.setPhone(request.getPhone());

        // Если пользователь передал ID категории бизнеса, находим ее и обновляем
        if (request.getTargetBusinessCategoryId() != null) {
            BusinessCategory category = businessCategoryRepository.findById(request.getTargetBusinessCategoryId())
                    .orElseThrow(() -> new RuntimeException("Категория бизнеса не найдена"));
            profile.setTargetBusinessCategory(category);
        }

        return tenantProfileRepository.save(profile);
    }

    // --- ЛОГИКА АРЕНДОДАТЕЛЯ (LANDLORD) ---

    @Transactional(readOnly = true)
    public LandlordProfile getLandlordProfile(Long userId) {
        LandlordProfile profile = landlordProfileRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Профиль арендодателя не найден"));
        userRepository.findById(userId).ifPresent(u -> profile.setAvatarUrl(u.getAvatarUrl()));
        return profile;
    }

    @Transactional
    public LandlordProfile updateLandlordProfile(Long userId, UpdateLandlordProfileRequest request) {
        LandlordProfile profile = getLandlordProfile(userId);

        profile.setCompanyName(request.getCompanyName());
        profile.setInn(request.getInn());
        profile.setPhone(request.getPhone());
        // isVerified мы не разрешаем менять самому пользователю (это делает админ)

        return landlordProfileRepository.save(profile);
    }

    // --- АВАТАРКА ---

    @Transactional
    public String uploadAvatar(Long userId, MultipartFile file) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        String oldUrl = user.getAvatarUrl();
        String newUrl = fileStorageService.store(file, "avatars/" + userId);
        user.setAvatarUrl(newUrl);
        userRepository.save(user);

        if (oldUrl != null) {
            fileStorageService.delete(oldUrl);
        }
        return newUrl;
    }

    @Transactional
    public void deleteAvatar(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));
        if (user.getAvatarUrl() != null) {
            fileStorageService.delete(user.getAvatarUrl());
            user.setAvatarUrl(null);
            userRepository.save(user);
        }
    }
}