package com.example.backend.dto;

import lombok.Data;

import java.math.BigDecimal;
import java.util.Set;

@Data
public class CreateSearchProfileRequest {

    private String name;                        // Название проекта

    private Long businessCategoryId;            // ID бизнес-категории

    // --- Финансовые критерии ---
    private BigDecimal minArea;                 // Мин. площадь, м²
    private BigDecimal maxArea;                 // Макс. площадь, м²
    private BigDecimal minBudget;               // Мин. бюджет, ₽/мес
    private BigDecimal maxBudget;               // Макс. бюджет, ₽/мес

    // --- Технические критерии ---
    private Integer minPowerKw;                 // Минимальная мощность, кВт
    private Boolean requiresWater;              // Нужна мокрая точка
    private Boolean requiresVentilation;        // Нужна вытяжка
    private Boolean requiresSeparateEntrance;   // Нужен отдельный вход

    // --- Локация ---
    private BigDecimal centerLatitude;          // Широта центра поиска
    private BigDecimal centerLongitude;         // Долгота центра поиска
    private Integer searchRadiusMeters;         // Радиус поиска в метрах

    // --- Синергичные соседи ---
    private Set<Long> desiredNeighborCategoryIds; // ID категорий желаемых соседей
}
