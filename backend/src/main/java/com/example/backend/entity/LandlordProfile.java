package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "landlord_profiles")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class LandlordProfile {

    @Id
    @Column(name = "user_id")
    private Long id;

    @OneToOne
    @MapsId
    @JoinColumn(name = "user_id")
    private User user;

    @Column(name = "company_name")
    private String companyName;

    private String inn;
    private String phone;

    @Column(name = "is_verified")
    private Boolean isVerified;
}