package com.example.backend.repository;

import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public interface PropertyRepository extends JpaRepository<Property, Long> {

    // Добавь этот метод в существующий PropertyRepository
    @Query("SELECT p FROM User u JOIN u.favoriteProperties p WHERE u.id = :tenantId")
    List<Property> findFavoritePropertiesByTenantId(@Param("tenantId") Long tenantId);
    List<Property> findByLandlordId(Long landlordId);

    List<Property> findByStatus(PropertyStatus status);

    @Query("SELECT p FROM Property p WHERE p.status = 'PUBLISHED' AND :category NOT MEMBER OF p.existingNeighbors")
    List<Property> findRecommendedPropertiesWithoutCompetitors(@Param("category") BusinessCategory category);

    List<Property> findByStatusAndHasSeparateEntranceTrueAndHasVentilationTrue(PropertyStatus status);
}