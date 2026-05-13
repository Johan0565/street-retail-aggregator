package com.example.backend.service;

import com.example.backend.dto.CreatePropertyRequest;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.*;
import com.example.backend.entity.enums.PropertyStatus;
import com.example.backend.repository.*;
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
    private final SearchProfileRepository searchProfileRepository;
    private final PropertyScoringService propertyScoringService;
    private final AnalyticsService analyticsService;

    /**
     * Получить рекомендованные помещения для арендатора.
     * Если у арендатора есть активный проект поиска — использует скоринг.
     * Если нет — возвращает все опубликованные без скоринга.
     */
    @Transactional(readOnly = true)
    public List<Property> getRecommendedPropertiesForTenant(Long tenantUserId) {
        List<Property> allPublished = propertyRepository.findByStatus(PropertyStatus.PUBLISHED);

        // Ищем активный проект поиска
        var activeProfiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantUserId);

        if (!activeProfiles.isEmpty()) {
            // Используем первый активный профиль для скоринга
            SearchProfile activeProfile = activeProfiles.get(0);
            return propertyScoringService
                    .scoreAndRankProperties(activeProfile, allPublished)
                    .stream()
                    .map(ScoredPropertyDto::getProperty)
                    .collect(Collectors.toList());
        }

        // Нет активного профиля — возвращаем без скоринга
        return allPublished;
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
                // Маппинг новых полей
                .propertyType(request.getPropertyType())
                .dealType(request.getDealType())
                .buildingName(request.getBuildingName())
                .buildingClass(request.getBuildingClass())
                .floor(request.getFloor())
                .totalFloors(request.getTotalFloors())
                .buildYear(request.getBuildYear())
                .taxIncluded(request.getTaxIncluded())
                .opexIncluded(request.getOpexIncluded())
                .utilityIncluded(request.getUtilityIncluded())
                .depositMonths(request.getDepositMonths())
                .rentHolidays(request.getRentHolidays())
                .legalAddressProvided(request.getLegalAddressProvided())
                .metroStation(request.getMetroStation())
                .timeToMetro(request.getTimeToMetro())
                .powerKw(request.getPowerKw())
                .hasWater(request.getHasWater())
                .hasVentilation(request.getHasVentilation())
                .hasSeparateEntrance(request.getHasSeparateEntrance())
                .repairState(request.getRepairState())
                .ceilingHeight(request.getCeilingHeight())
                .layout(request.getLayout())
                .parking(request.getParking())
                .security(request.getSecurity())
                .hasWc(request.getHasWc())
                .hasParking(request.getHasParking())
                .hasLoadingZone(request.getHasLoadingZone())
                .contactName(request.getContactName())
                .contactPhone(request.getContactPhone())
                .agentFee(request.getAgentFee())
                .status(PropertyStatus.PUBLISHED)
                .existingNeighbors(neighbors)
                .cadastralNumber(request.getCadastralNumber())
                .accessType(request.getAccessType())
                .heatingType(request.getHeatingType())
                .furnitureState(request.getFurnitureState())
                .isOccupied(request.getIsOccupied() != null ? request.getIsOccupied() : false)
                .build();

        return propertyRepository.save(property);
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
    @Transactional
    public void addFavorite(Long tenantId, Long propertyId) {
        User user = userRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        if (user.getFavoriteProperties() == null) {
            user.setFavoriteProperties(new java.util.HashSet<>());
        }
        boolean added = user.getFavoriteProperties().add(property);
        userRepository.save(user);
        if (added) {
            analyticsService.logFavoriteEvent(propertyId, tenantId);
        }
    }

    @Transactional
    public void removeFavorite(Long tenantId, Long propertyId) {
        User user = userRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        user.getFavoriteProperties().remove(property);
        userRepository.save(user);
    }

    @Transactional(readOnly = true)
    public List<Property> getFavorites(Long tenantId) {
        return propertyRepository.findFavoritePropertiesByTenantId(tenantId);
    }

    /**
     * Рассчитать скоринг конкретного помещения для арендатора с использованием
     * реальных данных 2GIS. Возвращает null, если нет активного профиля поиска.
     */
    @Transactional(readOnly = true)
    public ScoredPropertyDto scorePropertyForTenant(Long tenantId, Long propertyId) {
        var activeProfiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantId);
        if (activeProfiles.isEmpty()) return null;

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        return propertyScoringService.scorePropertyWithGis(activeProfiles.get(0), property);
    }

    @Transactional(readOnly = true)
    public SearchProfile findActiveProfile(Long tenantId) {
        var profiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantId);
        return profiles.isEmpty() ? null : profiles.get(0);
    }

    /**
     * Получить все опубликованные помещения (общая лента)
     */
    @Transactional(readOnly = true)
    public List<Property> getMyProperties(Long landlordId) {
        return propertyRepository.findByLandlordId(landlordId).stream()
                // ОТФИЛЬТРОВЫВАЕМ АРХИВНЫЕ (УДАЛЕННЫЕ) ПОМЕЩЕНИЯ
                .filter(property -> property.getStatus() != PropertyStatus.ARCHIVED)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<Property> getAllPublishedProperties() {
        return propertyRepository.findByStatus(PropertyStatus.PUBLISHED);
    }
}