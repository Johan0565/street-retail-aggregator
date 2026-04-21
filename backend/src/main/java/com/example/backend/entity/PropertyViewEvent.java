package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "property_view_events")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class PropertyViewEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    private Property property;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "viewer_id") // Nullable for anonymous views
    private User viewer;

    @CreationTimestamp
    @Column(name = "view_timestamp", updatable = false)
    private LocalDateTime viewTimestamp;
}
