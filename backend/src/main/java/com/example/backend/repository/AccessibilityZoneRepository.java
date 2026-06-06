package com.example.backend.repository;

import com.example.backend.entity.AccessibilityZone;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface AccessibilityZoneRepository extends JpaRepository<AccessibilityZone, Long> {
}
