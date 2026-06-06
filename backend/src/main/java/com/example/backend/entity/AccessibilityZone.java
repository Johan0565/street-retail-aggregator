package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "accessibility_zones")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class AccessibilityZone {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(name = "min_time_to_metro")
    private Integer minTimeToMetro;

    @Column(name = "max_time_to_metro")
    private Integer maxTimeToMetro;

    @Column(name = "accessibility_score")
    private Double accessibilityScore;
}
