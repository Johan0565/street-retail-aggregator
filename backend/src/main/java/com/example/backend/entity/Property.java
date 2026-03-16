package com.example.backend.entity;

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

    // Технические параметры
    @Column(name = "power_kw")
    private Integer powerKw;

    @Column(name = "has_water")
    private Boolean hasWater;

    @Column(name = "has_ventilation")
    private Boolean hasVentilation;

    @Column(name = "has_separate_entrance")
    private Boolean hasSeparateEntrance;

    @OneToMany(mappedBy = "property", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PropertyImage> images;

    @ManyToMany
    @JoinTable(
            name = "property_existing_neighbors",
            joinColumns = @JoinColumn(name = "property_id"),
            inverseJoinColumns = @JoinColumn(name = "category_id")
    )
    private Set<BusinessCategory> existingNeighbors;
}