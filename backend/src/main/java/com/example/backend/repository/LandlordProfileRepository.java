package com.example.backend.repository;
import com.example.backend.entity.LandlordProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.Optional;
@Repository
public interface LandlordProfileRepository extends JpaRepository<LandlordProfile, Long> {
    Optional<LandlordProfile> findByInn(String inn);
}