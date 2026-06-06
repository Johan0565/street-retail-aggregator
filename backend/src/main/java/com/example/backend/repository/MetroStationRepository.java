package com.example.backend.repository;

import com.example.backend.entity.MetroStation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface MetroStationRepository extends JpaRepository<MetroStation, Long> {
}
