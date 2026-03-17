package com.example.backend.service;

import com.example.backend.dto.CreatePropertyRequest;
import com.example.backend.entity.*;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.BusinessCategoryRepository;
import com.example.backend.repository.UserRepository;
import com.example.backend.repository.TenantProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class PropertyService {

    private final PropertyRepository propertyRepository;
    private final TenantProfileRepository tenantProfileRepository;
    private final UserRepository userRepository;
    private final BusinessCategoryRepository businessCategoryRepository;
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
    @Transactional
    public Property createProperty(Long landlordId, CreatePropertyRequest request) {
        User landlord = userRepository.findById(landlordId)
                .orElseThrow(() -> new RuntimeException("Арендодатель не найден"));

        // Ищем в базе категории соседей, которых указал арендодатель
        Set<BusinessCategory> neighbors = null;
        if (request.getExistingNeighborCategoryIds() != null && !request.getExistingNeighborCategoryIds().isEmpty()) {
            neighbors = new java.util.HashSet<>(
                    businessCategoryRepository.findAllById(request.getExistingNeighborCategoryIds())
            );
        }

        Property property = Property.builder()
                .landlord(landlord)
                .title(request.getTitle())
                .description(request.getDescription())
                .address(request.getAddress())
                .latitude(request.getLatitude())
                .longitude(request.getLongitude())
                .areaSqm(request.getAreaSqm())
                .pricePerMonth(request.getPricePerMonth())
                .powerKw(request.getPowerKw())
                .hasWater(request.getHasWater())
                .hasVentilation(request.getHasVentilation())
                .hasSeparateEntrance(request.getHasSeparateEntrance())
                .status(PropertyStatus.PUBLISHED) // Для тестов сразу публикуем
                .existingNeighbors(neighbors)
                .build();

        return propertyRepository.save(property);
    }
    @Transactional(readOnly = true)
    public List<Property> getMyProperties(Long landlordId) {
        return propertyRepository.findByLandlordId(landlordId);
    }

    /**
     * Обновить объявление
     */
    @Transactional
    public Property updateProperty(Long landlordId, Long propertyId, CreatePropertyRequest request) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        if (!property.getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("Нет прав на редактирование чужого объекта");
        }

        // Обновляем базовые поля
        property.setTitle(request.getTitle());
        property.setDescription(request.getDescription());
        property.setPricePerMonth(request.getPricePerMonth());
        // ... (здесь можно добавить обновление остальных полей по аналогии) ...

        return propertyRepository.save(property);
    }

    /**
     * Архивация (Удаление) объявления
     */
    @Transactional
    public void deleteProperty(Long landlordId, Long propertyId) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        if (!property.getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("Нет прав на удаление чужого объекта");
        }

        // В реальных системах данные не удаляют физически (repository.delete(property)),
        // а меняют статус на "В архиве", чтобы не сломать историю заявок.
        property.setStatus(PropertyStatus.ARCHIVED);
        propertyRepository.save(property);
    }
    // ... существующий код ...

    /**
     * Получить все опубликованные помещения (общая лента)
     */
    @Transactional(readOnly = true)
    public List<Property> getAllPublishedProperties() {
        return propertyRepository.findByStatus(PropertyStatus.PUBLISHED);
    }
}