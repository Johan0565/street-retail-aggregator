package com.example.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.util.List;

@Entity
@Table(name = "business_categories")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class BusinessCategory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "parent_id")
    @JsonIgnoreProperties({"parentCategory", "subCategories", "twoGisKeywords"})
    private BusinessCategory parentCategory;

    @JsonIgnore
    @OneToMany(mappedBy = "parentCategory")
    private List<BusinessCategory> subCategories;

    // Ключевые слова для сопоставления с рубриками 2GIS (через запятую, строчные)
    // Пример: "кофейня,кофе,coffee"
    @Column(name = "two_gis_keywords", columnDefinition = "TEXT")
    private String twoGisKeywords;
}