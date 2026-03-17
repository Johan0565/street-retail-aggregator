package com.example.backend.service;

import com.example.backend.dto.UpdateLandlordProfileRequest;
import com.example.backend.dto.UpdateTenantProfileRequest;
import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.LandlordProfile;
import com.example.backend.entity.TenantProfile;
import com.example.backend.repository.BusinessCategoryRepository;
import com.example.backend.repository.LandlordProfileRepository;
import com.example.backend.repository.TenantProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class ProfileService {

    private final TenantProfileRepository tenantProfileRepository;
    private final LandlordProfileRepository landlordProfileRepository;
    private final BusinessCategoryRepository businessCategoryRepository;

    // --- ЛОГИКА АРЕНДАТОРА (TENANT) ---

    @Transactional(readOnly = true)
    public TenantProfile getTenantProfile(Long userId) {
        return tenantProfileRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Профиль арендатора не найден"));
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
        return landlordProfileRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Профиль арендодателя не найден"));
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
}