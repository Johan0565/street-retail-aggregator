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
    @JsonIgnoreProperties({"parentCategory", "subCategories", "osmTags"})
    private BusinessCategory parentCategory;

    @JsonIgnore
    @OneToMany(mappedBy = "parentCategory")
    private List<BusinessCategory> subCategories;

    /**
     * OSM key=value-теги, по которым категория сопоставляется с результатами
     * Overpass API. CSV, нижний регистр. Пример: "amenity=pharmacy,shop=chemist".
     *
     * Колонка БД называется search_keywords по историческим причинам
     * (раньше тут лежали ключевые слова для Yandex Places API).
     */
    @Column(name = "search_keywords", columnDefinition = "TEXT")
    private String osmTags;
}
