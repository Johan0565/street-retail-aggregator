package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Set;

@Entity
@Table(name = "search_profiles")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SearchProfile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    private User tenant;

    @Column(nullable = false)
    private String name; // Например: "Открыть кофейню на Арбате"

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "business_category_id")
    private BusinessCategory businessCategory; // Тип бизнеса, который хочет открыть арендатор

    // --- 1. Финансовые критерии (20% скоринга) ---
    @Column(name = "min_area", precision = 10, scale = 2)
    private BigDecimal minArea;

    @Column(name = "max_area", precision = 10, scale = 2)
    private BigDecimal maxArea;

    @Column(name = "min_budget", precision = 12, scale = 2)
    private BigDecimal minBudget;

    @Column(name = "max_budget", precision = 12, scale = 2)
    private BigDecimal maxBudget;

    // --- 2. Технические критерии (20% скоринга) ---
    @Column(name = "min_power_kw")
    private Integer minPowerKw;

    @Column(name = "requires_water")
    private Boolean requiresWater;

    @Column(name = "requires_ventilation")
    private Boolean requiresVentilation;

    @Column(name = "requires_separate_entrance")
    private Boolean requiresSeparateEntrance;

    @Column(name = "requires_wc")
    private Boolean requiresWc;

    @Column(name = "requires_parking")
    private Boolean requiresParking;

    @Column(name = "requires_loading_zone")
    private Boolean requiresLoadingZone;

    @Column(name = "min_ceiling_height", precision = 4, scale = 2)
    private BigDecimal minCeilingHeight;

    // --- 3. Локация и синергия (25% скоринга) ---
    @Column(name = "center_latitude", precision = 10, scale = 8)
    private BigDecimal centerLatitude;

    @Column(name = "center_longitude", precision = 11, scale = 8)
    private BigDecimal centerLongitude;

    @Column(name = "search_radius_meters")
    private Integer searchRadiusMeters; // Радиус поиска конкурентов в метрах (например, 2000)

    // Отдельный радиус поиска желаемых соседей. Если null — используется
    // searchRadiusMeters (обратная совместимость со старыми проектами).
    @Column(name = "synergy_radius_meters")
    private Integer synergyRadiusMeters;

    // Категории бизнесов, с которыми хочет быть рядом (синергичные соседи)
    @ManyToMany
    @JoinTable(
            name = "search_profile_desired_neighbors",
            joinColumns = @JoinColumn(name = "search_profile_id"),
            inverseJoinColumns = @JoinColumn(name = "category_id")
    )
    private Set<BusinessCategory> desiredNeighbors;

    // --- Статус ---
    @Column(name = "is_active")
    @Builder.Default
    private Boolean isActive = true; // Активный проект поиска

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
