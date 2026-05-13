package com.example.backend.repository;

import com.example.backend.entity.Application;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public interface ApplicationRepository extends JpaRepository<Application, Long> {
    List<Application> findByTenantId(Long tenantId);
    List<Application> findByProperty_LandlordId(Long landlordId);
    List<Application> findByPropertyId(Long propertyId);

    List<Application> findByPropertyIdAndCreatedAtAfter(Long propertyId, java.time.LocalDateTime date);
    List<Application> findByProperty_LandlordIdAndCreatedAtAfter(Long landlordId, java.time.LocalDateTime date);
}