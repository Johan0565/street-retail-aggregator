package com.example.backend.service;

import java.util.List;

/**
 * Заведение из геопоиска. lat/lon — точка организации (0,0 если API не отдал
 * координаты для конкретного объекта).
 */
public record NearbyBusiness(String name, List<String> rubrics, double lat, double lon) {
    public NearbyBusiness(String name, List<String> rubrics) {
        this(name, rubrics, 0.0, 0.0);
    }
}
