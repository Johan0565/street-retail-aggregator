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
    private final PropertyScoreSnapshotService propertyScoreSnapshotService;
    private final AnalyticsService analyticsService;

    /**
     * Получить рекомендованные помещения для арендатора.
     * Если у арендатора есть активный проект поиска — использует скоринг
     * с snapshot-кэшем (повторное открытие списка не бьёт по Overpass).
     */
    @Transactional
    public List<Property> getRecommendedPropertiesForTenant(Long tenantUserId) {
        List<Property> allPublished = propertyRepository.findByStatus(PropertyStatus.PUBLISHED);

        var activeProfiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantUserId);

        if (!activeProfiles.isEmpty()) {
            SearchProfile activeProfile = activeProfiles.get(0);
            return propertyScoreSnapshotService
                    .scoreBatchWithSnapshot(activeProfile, allPublished, false)
                    .stream()
                    .map(ScoredPropertyDto::getProperty)
                    .collect(Collectors.toList());
        }

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
     * Обновить объявление. Инвалидируем кэш скоринга для этого помещения,
     * чтобы арендатор сразу увидел оценку под новые характеристики.
     */
    @Transactional
    public Property updateProperty(Long landlordId, Long propertyId, CreatePropertyRequest request) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        if (!property.getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("Нет прав на редактирование чужого объекта");
        }

        property.setTitle(request.getTitle());
        property.setDescription(request.getDescription());
        property.setPricePerMonth(request.getPricePerMonth());

        Property saved = propertyRepository.save(property);
        propertyScoreSnapshotService.invalidateByProperty(propertyId);
        return saved;
    }

    /**
     * Архивация объявления. Snapshot'ы тоже чистим — архивный объект
     * не должен болтаться в кэше скоринга.
     */
    @Transactional
    public void deleteProperty(Long landlordId, Long propertyId) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        if (!property.getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("Нет прав на удаление чужого объекта");
        }

        property.setStatus(PropertyStatus.ARCHIVED);
        propertyRepository.save(property);
        propertyScoreSnapshotService.invalidateByProperty(propertyId);
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
     * Рассчитать скоринг конкретного помещения для арендатора. Под капотом
     * — snapshot-кэш: если оценка свежая, возвращается мгновенно из БД,
     * иначе пересчитывается и сохраняется.
     *
     * @param profileId если задан — используется именно этот проект
     * @param force если true — игнорировать snapshot и форсировать пересчёт
     *              (для кнопки «обновить оценку»)
     */
    @Transactional
    public ScoredPropertyDto scorePropertyForTenant(Long tenantId, Long propertyId, Long profileId, boolean force) {
        SearchProfile profile = resolveProfile(tenantId, profileId);
        if (profile == null) return null;

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        return propertyScoreSnapshotService.scoreWithSnapshot(profile, property, force);
    }

    /** Совместимость со старыми вызовами без force-параметра. */
    @Transactional
    public ScoredPropertyDto scorePropertyForTenant(Long tenantId, Long propertyId, Long profileId) {
        return scorePropertyForTenant(tenantId, propertyId, profileId, false);
    }

    @Transactional(readOnly = true)
    public SearchProfile findProfileForTenant(Long tenantId, Long profileId) {
        return resolveProfile(tenantId, profileId);
    }

    private SearchProfile resolveProfile(Long tenantId, Long profileId) {
        if (profileId != null) {
            return searchProfileRepository.findById(profileId)
                    .filter(p -> p.getTenant() != null && tenantId.equals(p.getTenant().getId()))
                    .orElse(null);
        }
        var profiles = searchProfileRepository.findByTenantIdAndIsActiveTrue(tenantId);
        return profiles.isEmpty() ? null : profiles.get(0);
    }

    @Transactional(readOnly = true)
    public List<Property> getMyProperties(Long landlordId) {
        return propertyRepository.findByLandlordId(landlordId).stream()
                .filter(property -> property.getStatus() != PropertyStatus.ARCHIVED)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<Property> getAllPublishedProperties() {
        return propertyRepository.findByStatus(PropertyStatus.PUBLISHED);
    }
}
