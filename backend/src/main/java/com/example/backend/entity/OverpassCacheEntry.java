package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * Долгоживущий кэш Overpass-ответов в PostgreSQL. Дополняет in-memory
 * Caffeine: после рестарта retail-backend Caffeine очищается, и без этого
 * слоя весь Overpass-кэш холодный — каждое первое открытие списка после
 * деплоя бьёт по публичным mirror'ам.
 *
 * Ключ {@link #cacheKey} строится сервисом по той же логике, что у
 * Caffeine ({@code lat_round*1000 + lon_round*1000 + radius_bucket/250}),
 * так что Москва-плотные адреса попадают в общие бакеты и быстро прогревают
 * друг друга.
 */
@Entity
@Table(name = "overpass_cache",
        indexes = @Index(name = "idx_overpass_cache_key", columnList = "cache_key", unique = true))
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OverpassCacheEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "cache_key", nullable = false, unique = true, length = 64)
    private String cacheKey;

    /**
     * Сериализованный {@code OverpassAreaSnapshot} в JSON. TEXT, потому что
     * для плотных районов JSON может быть десятки/сотни килобайт.
     */
    @Column(name = "response_json", nullable = false, columnDefinition = "TEXT")
    private String responseJson;

    @Column(name = "cached_at", nullable = false)
    private LocalDateTime cachedAt;
}
