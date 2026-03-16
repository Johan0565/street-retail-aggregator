package com.example.backend.service;

import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyStatus;
import com.example.backend.entity.TenantProfile;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.TenantProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class PropertyService {

    private final PropertyRepository propertyRepository;
    private final TenantProfileRepository tenantProfileRepository;

    @Transactional(readOnly = true)
    public List<Property> getRecommendedPropertiesForTenant(Long tenantUserId) {
        TenantProfile tenant = tenantProfileRepository.findById(tenantUserId)
                .orElseThrow(() -> new RuntimeException("Профиль арендатора не найден"));

        BusinessCategory targetCategory = tenant.getTargetBusinessCategory();

        List<Property> allPublishedProperties = propertyRepository.findByStatus(PropertyStatus.PUBLISHED);

        return allPublishedProperties.stream()
                .sorted((p1, p2) -> Integer.compare(
                        calculateRecommendationScore(p2, targetCategory),
                        calculateRecommendationScore(p1, targetCategory)
                ))
                .collect(Collectors.toList());
    }

    private int calculateRecommendationScore(Property property, BusinessCategory targetCategory) {
        int score = 100;

        boolean hasDirectCompetitor = property.getExistingNeighbors().stream()
                .anyMatch(neighborCategory -> neighborCategory.getId().equals(targetCategory.getId()));

        if (hasDirectCompetitor) {
            score -= 80;
        }

        if (targetCategory.getId() == 3L && !property.getHasWater()) {
            score -= 50;
        }

        return score;
    }

    @Transactional(readOnly = true)
    public Property getPropertyById(Long id) {
        return propertyRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));
    }
}