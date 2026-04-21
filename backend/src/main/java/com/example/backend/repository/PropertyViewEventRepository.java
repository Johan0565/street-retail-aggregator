package com.example.backend.repository;

import com.example.backend.entity.PropertyViewEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface PropertyViewEventRepository extends JpaRepository<PropertyViewEvent, Long> {
    List<PropertyViewEvent> findByPropertyLandlordIdAndViewTimestampAfter(Long landlordId, LocalDateTime date);
}
