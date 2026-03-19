package com.example.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import java.time.LocalDateTime;
import java.util.Set;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import java.util.Collection;
import java.util.List;

@Entity
@Table(name = "users")
@Data @NoArgsConstructor @AllArgsConstructor @Builder
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
public class User implements UserDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String email;

    @JsonIgnore
    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    @Enumerated(EnumType.STRING)
    private UserStatus status;

    @Column(name = "verification_code")
    @JsonIgnore
    private String verificationCode;

    @Column(name = "code_expires_at")
    @JsonIgnore
    private LocalDateTime codeExpiresAt;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    @JsonIgnore
    private LocalDateTime createdAt;

    @OneToOne(mappedBy = "user", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private TenantProfile tenantProfile;

    @OneToOne(mappedBy = "user", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private LandlordProfile landlordProfile;
    @Override
    @JsonIgnore
    public Collection<? extends GrantedAuthority> getAuthorities() {
        // Возвращаем роль пользователя, добавляя префикс "ROLE_", как того требует Spring Security
        return List.of(new SimpleGrantedAuthority("ROLE_" + role.name()));
    }

    @Override
    public String getUsername() {
        return email; // В качестве логина используем email
    }

    @Override
    @JsonIgnore
    public String getPassword() {
        return passwordHash; // Возвращаем захэшированный пароль
    }
    // Избранное (Связь Many-to-Many с Property)
    @ManyToMany
    @JoinTable(
            name = "favorites",
            joinColumns = @JoinColumn(name = "tenant_id"),
            inverseJoinColumns = @JoinColumn(name = "property_id")
    )
    private Set<Property> favoriteProperties;
    @Override
    @JsonIgnore
    public boolean isAccountNonExpired() { return true; }
    @Override
    @JsonIgnore
    public boolean isAccountNonLocked() { return status != UserStatus.BANNED; }
    @Override
    @JsonIgnore
    public boolean isCredentialsNonExpired() { return true; }
    @Override
    @JsonIgnore
    public boolean isEnabled() { return status == UserStatus.ACTIVE; }
}