package com.example.backend.dto;

import lombok.Builder;
import lombok.Data;
import java.util.Map;
import java.util.List;

@Data
@Builder
public class AnalyticsDto {
    private long totalViewsLast30Days;
    private long totalApplications;
    private long totalFavorites;
    private Map<String, Long> viewsByDate;
    private List<PropertyStatDto> propertyStats;

    @Data
    @Builder
    public static class PropertyStatDto {
        private Long propertyId;
        private String title;
        private long views;
        private long applications;
        private long favorites;
    }
}
