package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "tenant_profiles")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class TenantProfile {

    @Id
    @Column(name = "user_id")
    private Long id;

    @OneToOne
    @MapsId
    @JoinColumn(name = "user_id")
    private User user;

    private String name;

    @Column(unique = true)
    private String inn;

    private String phone;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "target_business_category_id")
    private BusinessCategory targetBusinessCategory;
}