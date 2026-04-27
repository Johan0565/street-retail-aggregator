package com.example.backend.service;

import com.example.backend.dto.AnalyticsDto;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyViewEvent;
import com.example.backend.entity.User;
import com.example.backend.repository.ApplicationRepository;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.PropertyViewEventRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AnalyticsService {

    private final PropertyViewEventRepository propertyViewEventRepository;
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

    public AnalyticsDto getLandlordAnalytics(Long landlordId) {
        LocalDateTime thirtyDaysAgo = LocalDateTime.now().minusDays(30);

        List<PropertyViewEvent> recentViews = propertyViewEventRepository
                .findByPropertyLandlordIdAndViewTimestampAfter(landlordId, thirtyDaysAgo);

        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd");
        Map<String, Long> viewsByDate = recentViews.stream()
                .collect(Collectors.groupingBy(
                        e -> e.getViewTimestamp().format(formatter),
                        Collectors.counting()
                ));

        List<Property> properties = propertyRepository.findByLandlordId(landlordId);
        long totalApplications = 0;
        long totalFavorites = propertyRepository.countFavoritesByLandlordId(landlordId);
        List<AnalyticsDto.PropertyStatDto> propertyStats = new ArrayList<>();
        
        for (Property p : properties) {
            long pApps = applicationRepository.findByPropertyId(p.getId()).size();
            totalApplications += pApps;
            long pViews = recentViews.stream().filter(e -> e.getProperty().getId().equals(p.getId())).count();
            long pFavs = propertyRepository.countFavoritesByPropertyId(p.getId());
            
            propertyStats.add(AnalyticsDto.PropertyStatDto.builder()
                    .propertyId(p.getId())
                    .title(p.getTitle())
                    .views(pViews)
                    .applications(pApps)
                    .favorites(pFavs)
                    .build());
        }

        return AnalyticsDto.builder()
                .totalViewsLast30Days(recentViews.size())
                .totalApplications(totalApplications)
                .totalFavorites(totalFavorites)
                .viewsByDate(viewsByDate)
                .propertyStats(propertyStats)
                .build();
    }
}
