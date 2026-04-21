package com.example.backend.repository;

import com.example.backend.entity.SearchProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface SearchProfileRepository extends JpaRepository<SearchProfile, Long> {

    // Все проекты поиска конкретного арендатора
    List<SearchProfile> findByTenantId(Long tenantId);

    // Только активные проекты арендатора
    List<SearchProfile> findByTenantIdAndIsActiveTrue(Long tenantId);
}
