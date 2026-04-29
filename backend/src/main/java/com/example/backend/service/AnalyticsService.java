package com.example.backend.service;

import com.example.backend.dto.AnalyticsDto;
import com.example.backend.entity.FavoriteEvent;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyViewEvent;
import com.example.backend.entity.User;
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

    public AnalyticsDto getLandlordAnalytics(Long landlordId) {
        LocalDateTime thirtyDaysAgo = LocalDateTime.now().minusDays(30);
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd");

        // Просмотры
        List<PropertyViewEvent> recentViews = propertyViewEventRepository
                .findByPropertyLandlordIdAndViewTimestampAfter(landlordId, thirtyDaysAgo);
        Map<String, Long> viewsByDate = recentViews.stream()
                .collect(Collectors.groupingBy(
                        e -> e.getViewTimestamp().format(formatter),
                        Collectors.counting()
                ));

        // Лайки (избранное)
        List<FavoriteEvent> recentFavorites = favoriteEventRepository
                .findByPropertyLandlordIdAndCreatedAtAfter(landlordId, thirtyDaysAgo);
        Map<String, Long> favoritesByDate = recentFavorites.stream()
                .collect(Collectors.groupingBy(
                        e -> e.getCreatedAt().format(formatter),
                        Collectors.counting()
                ));

        // Заявки
        List<Property> properties = propertyRepository.findByLandlordId(landlordId);
        long totalApplications = 0;
        for (Property p : properties) {
            totalApplications += applicationRepository.findByPropertyId(p.getId()).size();
        }

        // Уникальные арендаторы, написавшие сообщения
        long totalUniqueMessengers = chatRoomRepository.countDistinctTenantsByLandlordId(landlordId);

        return AnalyticsDto.builder()
                .totalViewsLast30Days(recentViews.size())
                .totalFavoritesLast30Days(recentFavorites.size())
                .totalApplications(totalApplications)
                .totalUniqueMessengers(totalUniqueMessengers)
                .viewsByDate(viewsByDate)
                .favoritesByDate(favoritesByDate)
                .build();
    }
}
