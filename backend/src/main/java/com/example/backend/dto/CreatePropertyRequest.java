package com.example.backend.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.util.Set;

@Data
public class CreatePropertyRequest {
    private String title;
    private String description;
    private String address;
    private BigDecimal latitude;
    private BigDecimal longitude;
    private BigDecimal areaSqm;
    private BigDecimal pricePerMonth;

    // Технические характеристики
    private Integer powerKw;
    private Boolean hasWater;
    private Boolean hasVentilation;
    private Boolean hasSeparateEntrance;

    // Передаем ID категорий бизнесов, которые уже есть в этом здании
    private Set<Long> existingNeighborCategoryIds;
}