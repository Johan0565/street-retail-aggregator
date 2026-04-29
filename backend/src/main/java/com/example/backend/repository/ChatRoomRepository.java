package com.example.backend.repository;

import com.example.backend.entity.ChatRoom;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {
    Optional<ChatRoom> findByApplicationId(Long applicationId);
    List<ChatRoom> findByLandlordIdOrTenantId(Long landlordId, Long tenantId);

    @Query("SELECT COUNT(DISTINCT c.tenant.id) FROM ChatRoom c WHERE c.landlord.id = :landlordId")
    long countDistinctTenantsByLandlordId(@Param("landlordId") Long landlordId);
}
