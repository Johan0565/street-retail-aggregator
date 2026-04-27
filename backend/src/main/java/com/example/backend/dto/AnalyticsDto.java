package com.example.backend.dto;

import lombok.Builder;
import lombok.Data;
import java.util.Map;

@Data
@Builder
public class AnalyticsDto {
    private long totalViewsLast30Days;
    private long totalApplications;
    private long totalFavorites;
    private Map<String, Long> viewsByDate;
}
