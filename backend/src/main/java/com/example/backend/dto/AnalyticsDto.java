package com.example.backend.dto;

import lombok.Builder;
import lombok.Data;
import java.util.Map;

@Data
@Builder
public class AnalyticsDto {
    private long totalViewsLast30Days;
    private long totalFavoritesLast30Days;
    private long totalApplications;
    private long totalUniqueMessengers;
    private long totalApplicationsLast30Days;
    private Map<String, Long> viewsByDate;
    private Map<String, Long> favoritesByDate;
    private Map<String, Long> applicationsByDate;
    // Заполняется только для аналитики по конкретному помещению
    private Long propertyId;
    private String propertyTitle;
}
