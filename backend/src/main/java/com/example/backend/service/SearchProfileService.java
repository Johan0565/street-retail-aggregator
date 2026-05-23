package com.example.backend.service;

import com.example.backend.dto.CreateSearchProfileRequest;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.SearchProfile;
import com.example.backend.entity.User;
import com.example.backend.entity.enums.PropertyStatus;
import com.example.backend.repository.BusinessCategoryRepository;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.SearchProfileRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class SearchProfileService {

    private final SearchProfileRepository searchProfileRepository;
    private final UserRepository userRepository;
    private final BusinessCategoryRepository businessCategoryRepository;
    private final PropertyRepository propertyRepository;
    private final PropertyScoringService propertyScoringService;

    /**
     * Создать новый проект поиска.
     */
    @Transactional
    public SearchProfile createSearchProfile(Long tenantId, CreateSearchProfileRequest request) {
        User tenant = userRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        SearchProfile profile = buildProfileFromRequest(request, tenant);
        return searchProfileRepository.save(profile);
    }

    /**
     * Обновить существующий проект поиска.
     */
    @Transactional
    public SearchProfile updateSearchProfile(Long tenantId, Long profileId, CreateSearchProfileRequest request) {
        SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);

        // Обновляем поля
        profile.setName(request.getName());

        if (request.getBusinessCategoryId() != null) {
            BusinessCategory category = businessCategoryRepository.findById(request.getBusinessCategoryId())
                    .orElseThrow(() -> new RuntimeException("Категория не найдена"));
            profile.setBusinessCategory(category);
        }

        profile.setMinArea(request.getMinArea());
        profile.setMaxArea(request.getMaxArea());
        profile.setMinBudget(request.getMinBudget());
        profile.setMaxBudget(request.getMaxBudget());
        profile.setMinPowerKw(request.getMinPowerKw());
        profile.setRequiresWater(request.getRequiresWater());
        profile.setRequiresVentilation(request.getRequiresVentilation());
        profile.setRequiresSeparateEntrance(request.getRequiresSeparateEntrance());
        profile.setRequiresWc(request.getRequiresWc());
        profile.setRequiresParking(request.getRequiresParking());
        profile.setRequiresLoadingZone(request.getRequiresLoadingZone());
        profile.setMinCeilingHeight(request.getMinCeilingHeight());
        profile.setCenterLatitude(request.getCenterLatitude());
        profile.setCenterLongitude(request.getCenterLongitude());
        profile.setSearchRadiusMeters(request.getSearchRadiusMeters());
        profile.setSynergyRadiusMeters(request.getSynergyRadiusMeters());
        profile.setDesiredNeighbors(resolveCategories(request.getDesiredNeighborCategoryIds()));

        return searchProfileRepository.save(profile);
    }

    /**
     * Получить все проекты поиска текущего арендатора.
     */
    @Transactional(readOnly = true)
    public List<SearchProfile> getMySearchProfiles(Long tenantId) {
        return searchProfileRepository.findByTenantId(tenantId);
    }

    /**
     * Получить один проект по ID (с проверкой прав доступа).
     */
    @Transactional(readOnly = true)
    public SearchProfile getSearchProfileById(Long tenantId, Long profileId) {
        return getProfileOwnedByTenant(tenantId, profileId);
    }

    /**
     * Удалить проект поиска.
     */
    @Transactional
    public void deleteSearchProfile(Long tenantId, Long profileId) {
        SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);
        searchProfileRepository.delete(profile);
    }

    /**
     * ⭐ Ключевой метод: получить все опубликованные помещения со скорингом
     * по конкретному профилю поиска, отсортированных по убыванию балла.
     */
    @Transactional(readOnly = true)
    public List<ScoredPropertyDto> getScoredPropertiesForProfile(Long tenantId, Long profileId) {
        SearchProfile profile = getProfileOwnedByTenant(tenantId, profileId);

        // Загружаем все опубликованные помещения
        var allPublished = propertyRepository.findByStatus(PropertyStatus.PUBLISHED);

        // Оцениваем и сортируем
        return propertyScoringService.scoreAndRankProperties(profile, allPublished);
    }

    // -------------------------------------------------------------------------
    //  Вспомогательные методы
    // -------------------------------------------------------------------------

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
                .minArea(request.getMinArea())
                .maxArea(request.getMaxArea())
                .minBudget(request.getMinBudget())
                .maxBudget(request.getMaxBudget())
                .minPowerKw(request.getMinPowerKw())
                .requiresWater(request.getRequiresWater())
                .requiresVentilation(request.getRequiresVentilation())
                .requiresSeparateEntrance(request.getRequiresSeparateEntrance())
                .requiresWc(request.getRequiresWc())
                .requiresParking(request.getRequiresParking())
                .requiresLoadingZone(request.getRequiresLoadingZone())
                .minCeilingHeight(request.getMinCeilingHeight())
                .centerLatitude(request.getCenterLatitude())
                .centerLongitude(request.getCenterLongitude())
                .searchRadiusMeters(request.getSearchRadiusMeters())
                .synergyRadiusMeters(request.getSynergyRadiusMeters())
                .desiredNeighbors(resolveCategories(request.getDesiredNeighborCategoryIds()))
                .isActive(true)
                .build();
    }

    private Set<BusinessCategory> resolveCategories(Set<Long> ids) {
        if (ids == null || ids.isEmpty()) return new HashSet<>();
        return new HashSet<>(businessCategoryRepository.findAllById(ids));
    }

    private SearchProfile getProfileOwnedByTenant(Long tenantId, Long profileId) {
        SearchProfile profile = searchProfileRepository.findById(profileId)
                .orElseThrow(() -> new RuntimeException("Проект поиска не найден"));
        if (!profile.getTenant().getId().equals(tenantId)) {
            throw new RuntimeException("Нет прав доступа к этому проекту поиска");
        }
        return profile;
    }
}
