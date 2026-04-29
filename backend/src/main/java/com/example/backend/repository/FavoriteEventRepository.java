package com.example.backend.repository;

import com.example.backend.entity.FavoriteEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface FavoriteEventRepository extends JpaRepository<FavoriteEvent, Long> {
    List<FavoriteEvent> findByPropertyLandlordIdAndCreatedAtAfter(Long landlordId, LocalDateTime date);
}
