package com.example.backend.repository;

import com.example.backend.entity.OverpassCacheEntry;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Optional;

public interface OverpassCacheRepository extends JpaRepository<OverpassCacheEntry, Long> {

    Optional<OverpassCacheEntry> findByCacheKey(String cacheKey);

    /**
     * Удаляет устаревшие записи. Вызывается фоновым scheduled-таском
     * (см. {@code OverpassCacheService.cleanupExpired}). Без этого таблица
     * будет неограниченно расти.
     */
    @Modifying
    @Query("DELETE FROM OverpassCacheEntry e WHERE e.cachedAt < :cutoff")
    int deleteByCachedAtBefore(@Param("cutoff") LocalDateTime cutoff);
}
