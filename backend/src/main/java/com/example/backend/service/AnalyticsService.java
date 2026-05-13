package com.example.backend.service;

import com.example.backend.dto.AnalyticsDto;
import com.example.backend.entity.Application;
import com.example.backend.entity.FavoriteEvent;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyViewEvent;
import com.example.backend.entity.User;
import com.example.backend.entity.enums.PropertyStatus;
import com.example.backend.repository.ApplicationRepository;
import com.example.backend.repository.ChatRoomRepository;
import com.example.backend.repository.FavoriteEventRepository;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.PropertyViewEventRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AnalyticsService {

    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    private final PropertyViewEventRepository propertyViewEventRepository;
    private final FavoriteEventRepository favoriteEventRepository;
    private final ChatRoomRepository chatRoomRepository;
    private final PropertyRepository propertyRepository;
    private final ApplicationRepository applicationRepository;
    private final UserRepository userRepository;

    public void logPropertyView(Long propertyId, Long viewerId) {
        Property property = propertyRepository.findById(propertyId).orElse(null);
        if (property == null) return;

        User viewer = null;
        if (viewerId != null) {
            viewer = userRepository.findById(viewerId).orElse(null);
        }

        PropertyViewEvent event = PropertyViewEvent.builder()
                .property(property)
                .viewer(viewer)
                .build();
        propertyViewEventRepository.save(event);
    }

    public void logFavoriteEvent(Long propertyId, Long tenantId) {
        Property property = propertyRepository.findById(propertyId).orElse(null);
        if (property == null) return;

        User tenant = null;
        if (tenantId != null) {
            tenant = userRepository.findById(tenantId).orElse(null);
        }

        FavoriteEvent event = FavoriteEvent.builder()
                .property(property)
                .tenant(tenant)
                .build();
        favoriteEventRepository.save(event);
    }

    /**
     * Сводная аналитика по всем НЕ архивным помещениям лендлорда за 30 дней.
     */
    public AnalyticsDto getLandlordAnalytics(Long landlordId) {
        LocalDateTime thirtyDaysAgo = LocalDateTime.now().minusDays(30);

        List<PropertyViewEvent> recentViews = propertyViewEventRepository
                .findByPropertyLandlordIdAndViewTimestampAfter(landlordId, thirtyDaysAgo)
                .stream()
                .filter(e -> isNotArchived(e.getProperty()))
                .collect(Collectors.toList());

        List<FavoriteEvent> recentFavorites = favoriteEventRepository
                .findByPropertyLandlordIdAndCreatedAtAfter(landlordId, thirtyDaysAgo)
                .stream()
                .filter(e -> isNotArchived(e.getProperty()))
                .collect(Collectors.toList());

        List<Application> recentApps = applicationRepository
                .findByProperty_LandlordIdAndCreatedAtAfter(landlordId, thirtyDaysAgo)
                .stream()
                .filter(a -> isNotArchived(a.getProperty()))
                .collect(Collectors.toList());

        // Все заявки за всё время (по неархивным помещениям)
        List<Property> activeProperties = propertyRepository.findByLandlordId(landlordId).stream()
                .filter(this::isNotArchived)
                .collect(Collectors.toList());
        long totalApplications = 0;
        for (Property p : activeProperties) {
            totalApplications += applicationRepository.findByPropertyId(p.getId()).size();
        }

        long totalUniqueMessengers = chatRoomRepository.countDistinctTenantsByLandlordId(landlordId);

        return AnalyticsDto.builder()
                .totalViewsLast30Days(recentViews.size())
                .totalFavoritesLast30Days(recentFavorites.size())
                .totalApplications(totalApplications)
                .totalApplicationsLast30Days(recentApps.size())
                .totalUniqueMessengers(totalUniqueMessengers)
                .viewsByDate(groupViewsByDate(recentViews))
                .favoritesByDate(groupFavoritesByDate(recentFavorites))
                .applicationsByDate(groupApplicationsByDate(recentApps))
                .build();
    }

    /**
     * Аналитика по конкретному помещению за 30 дней.
     * Проверка владельца — на уровне контроллера.
     */
    public AnalyticsDto getPropertyAnalytics(Long propertyId) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        LocalDateTime thirtyDaysAgo = LocalDateTime.now().minusDays(30);

        List<PropertyViewEvent> views = propertyViewEventRepository
                .findByPropertyIdAndViewTimestampAfter(propertyId, thirtyDaysAgo);
        List<FavoriteEvent> favorites = favoriteEventRepository
                .findByPropertyIdAndCreatedAtAfter(propertyId, thirtyDaysAgo);
        List<Application> recentApps = applicationRepository
                .findByPropertyIdAndCreatedAtAfter(propertyId, thirtyDaysAgo);
        long totalApplications = applicationRepository.findByPropertyId(propertyId).size();

        return AnalyticsDto.builder()
                .totalViewsLast30Days(views.size())
                .totalFavoritesLast30Days(favorites.size())
                .totalApplications(totalApplications)
                .totalApplicationsLast30Days(recentApps.size())
                .totalUniqueMessengers(0L) // на уровне одного помещения не считаем
                .viewsByDate(groupViewsByDate(views))
                .favoritesByDate(groupFavoritesByDate(favorites))
                .applicationsByDate(groupApplicationsByDate(recentApps))
                .propertyId(propertyId)
                .propertyTitle(property.getTitle())
                .build();
    }

    public boolean isOwner(Long propertyId, Long landlordId) {
        return propertyRepository.findById(propertyId)
                .map(p -> p.getLandlord() != null && landlordId.equals(p.getLandlord().getId()))
                .orElse(false);
    }

    private boolean isNotArchived(Property property) {
        return property != null && property.getStatus() != PropertyStatus.ARCHIVED;
    }

    private Map<String, Long> groupViewsByDate(List<PropertyViewEvent> events) {
        return events.stream().collect(Collectors.groupingBy(
                e -> e.getViewTimestamp().format(DATE_FORMATTER),
                Collectors.counting()));
    }

    private Map<String, Long> groupFavoritesByDate(List<FavoriteEvent> events) {
        return events.stream().collect(Collectors.groupingBy(
                e -> e.getCreatedAt().format(DATE_FORMATTER),
                Collectors.counting()));
    }

    private Map<String, Long> groupApplicationsByDate(List<Application> apps) {
        return apps.stream().collect(Collectors.groupingBy(
                a -> a.getCreatedAt().format(DATE_FORMATTER),
                Collectors.counting()));
    }
}
