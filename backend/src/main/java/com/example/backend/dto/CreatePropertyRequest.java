package com.example.backend.dto;

import com.example.backend.entity.*;
import com.example.backend.entity.enums.*;
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

    // 1. Базовые
    private PropertyType propertyType;
    private DealType dealType;
    private String buildingName;
    private BuildingClass buildingClass;
    private Integer floor;
    private Integer totalFloors;
    private Integer buildYear;

    // 2. Финансы
    private Boolean taxIncluded;
    private Boolean opexIncluded;
    private Boolean utilityIncluded;
    private Integer depositMonths;
    private Boolean rentHolidays;
    private Boolean legalAddressProvided;

    // 3. Локация
    private String metroStation;
    private Integer timeToMetro;

    // 4. Технические
    private Integer powerKw;
    private Boolean hasWater;
    private Boolean hasVentilation;
    private Boolean hasSeparateEntrance;
    private RepairState repairState;
    private BigDecimal ceilingHeight;
    private LayoutType layout;

    // 5. Инфраструктура
    private String parking;
    private String security;
    private Boolean hasWc;
    private Boolean hasParking;
    private Boolean hasLoadingZone;

    // 6. Контакты
    private String contactName;
    private String contactPhone;
    private BigDecimal agentFee;

    private String cadastralNumber;
    private AccessType accessType;
    private HeatingType heatingType;
    private FurnitureState furnitureState;
    private Boolean isOccupied;

    private Set<Long> existingNeighborCategoryIds;
}