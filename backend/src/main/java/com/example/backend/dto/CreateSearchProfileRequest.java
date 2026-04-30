package com.example.backend.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Set;


@Data
public class CreateSearchProfileRequest {

    @NotBlank(message = "Название проекта не может быть пустым")
    @Size(max = 255, message = "Название не должно превышать 255 символов")
    private String name;

    @NotNull(message = "Категория бизнеса обязательна")
    private Long businessCategoryId;

    // --- Финансовые критерии ---
    @DecimalMin(value = "0", message = "Минимальная площадь не может быть отрицательной")
    private BigDecimal minArea;

    @DecimalMin(value = "0", message = "Максимальная площадь не может быть отрицательной")
    private BigDecimal maxArea;

    @DecimalMin(value = "0", message = "Минимальный бюджет не может быть отрицательным")
    private BigDecimal minBudget;

    @DecimalMin(value = "0", message = "Максимальный бюджет не может быть отрицательным")
    private BigDecimal maxBudget;

    // --- Технические критерии ---
    @Min(value = 0, message = "Мощность не может быть отрицательной")
    private Integer minPowerKw;

    private Boolean requiresWater;
    private Boolean requiresVentilation;
    private Boolean requiresSeparateEntrance;
    private Boolean requiresWc;
    private Boolean requiresParking;
    private Boolean requiresLoadingZone;

    @DecimalMin(value = "0", message = "Высота потолков не может быть отрицательной")
    private BigDecimal minCeilingHeight;

    // --- Локация ---
    private BigDecimal centerLatitude;
    private BigDecimal centerLongitude;

    @Min(value = 0, message = "Радиус поиска не может быть отрицательным")
    private Integer searchRadiusMeters;

    // --- Синергичные соседи ---
    private Set<Long> desiredNeighborCategoryIds;
}
