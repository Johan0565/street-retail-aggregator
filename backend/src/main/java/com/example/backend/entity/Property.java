package com.example.backend.entity;

import com.example.backend.entity.enums.*;
import com.example.backend.entity.enums.AccessType;
import com.example.backend.entity.enums.FurnitureState;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.util.Set;
import java.util.List;

@Entity
@Table(name = "properties")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class Property {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "landlord_id", nullable = false)
    private User landlord;

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description;

    private String address;

    @Column(precision = 10, scale = 8)
    private BigDecimal latitude;

    @Column(precision = 11, scale = 8)
    private BigDecimal longitude;

    @Column(name = "area_sqm", precision = 10, scale = 2)
    private BigDecimal areaSqm;

    @Column(name = "price_per_month", precision = 12, scale = 2)
    private BigDecimal pricePerMonth;

    @Enumerated(EnumType.STRING)
    private PropertyStatus status;

    // --- 1. Базовая информация ---
    @Enumerated(EnumType.STRING)
    private PropertyType propertyType;

    @Enumerated(EnumType.STRING)
    private DealType dealType;

    private String buildingName;

    @Enumerated(EnumType.STRING)
    private BuildingClass buildingClass;

    private Integer floor;
    private Integer totalFloors;
    private Integer buildYear;

    // --- 2. Финансовые условия ---
    private Boolean taxIncluded;
    private Boolean opexIncluded;
    private Boolean utilityIncluded;
    private Integer depositMonths;
    private Boolean rentHolidays;
    private Boolean legalAddressProvided;

    // --- 3. Локация и доступность ---
    private String metroStation;
    private Integer timeToMetro; // в минутах

    // --- 4. Технические характеристики ---
    @Column(name = "power_kw")
    private Integer powerKw;

    @Column(name = "has_water")
    private Boolean hasWater;

    @Column(name = "has_ventilation")
    private Boolean hasVentilation;

    @Column(name = "has_separate_entrance")
    private Boolean hasSeparateEntrance;

    @Enumerated(EnumType.STRING)
    private RepairState repairState;

    @Column(precision = 4, scale = 2)
    private BigDecimal ceilingHeight;

    @Enumerated(EnumType.STRING)
    private LayoutType layout;

    // --- 5. Инфраструктура ---
    private String parking;
    private String security;

    // --- 6. Контакты ---
    private String contactName;
    private String contactPhone;

    @Column(precision = 5, scale = 2)
    private BigDecimal agentFee; // % комиссии (0 если без комиссии)

    @OneToMany(mappedBy = "property", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PropertyImage> images;

    @ManyToMany
    @JoinTable(
            name = "property_existing_neighbors",
            joinColumns = @JoinColumn(name = "property_id"),
            inverseJoinColumns = @JoinColumn(name = "category_id")
    )
    private Set<BusinessCategory> existingNeighbors;
    private String cadastralNumber;

    @Enumerated(EnumType.STRING)
    private AccessType accessType;

    @Enumerated(EnumType.STRING)
    private HeatingType heatingType;

    @Enumerated(EnumType.STRING)
    private FurnitureState furnitureState;

    @Column(name = "is_occupied")
    private Boolean isOccupied; // Сдается сейчас или пустует
}