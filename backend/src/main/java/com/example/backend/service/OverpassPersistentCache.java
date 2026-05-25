package com.example.backend.service;

import com.example.backend.entity.OverpassCacheEntry;
import com.example.backend.repository.OverpassCacheRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Optional;

/**
 * Долгоживущий слой кэша Overpass-ответов поверх PostgreSQL. Дополняет
 * in-memory Caffeine: после рестарта retail-backend Caffeine пуст, и без
 * этого слоя весь скоринг бьёт по публичным mirror'ам Overpass с холодным
 * стартом.
 *
 * TTL по умолчанию 7 дней — OSM-данные меняются медленно (новый ТЦ/станция
 * метро — события месяца), а Overpass — самое нестабильное звено в системе,
 * лучше отдать чуть устаревшие данные, чем «не удалось оценить».
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class OverpassPersistentCache {

    private final OverpassCacheRepository repository;
    private final ObjectMapper objectMapper;

    @Value("${overpass.cache.ttl-hours:168}")
    private long ttlHours;

    /**
     * Возвращает кэшированный snapshot, если запись свежее TTL. Сериализуем
     * только OK-снапшоты (см. {@link #put}), так что найденная запись по
     * определению успешная.
     */
    @Transactional(readOnly = true)
    public Optional<OverpassAreaSnapshot> get(String cacheKey) {
        Optional<OverpassCacheEntry> entry = repository.findByCacheKey(cacheKey);
        if (entry.isEmpty()) return Optional.empty();

        OverpassCacheEntry e = entry.get();
        LocalDateTime cutoff = LocalDateTime.now().minusHours(ttlHours);
        if (e.getCachedAt().isBefore(cutoff)) {
            // Устаревшая запись — игнорируем (фоновый cleanup удалит её отдельно).
            return Optional.empty();
        }
        try {
            OverpassAreaSnapshot snapshot = objectMapper.readValue(e.getResponseJson(), OverpassAreaSnapshot.class);
            return Optional.of(snapshot);
        } catch (Exception ex) {
            // Битая запись (например, после смены формата). Не эвиктим её
            // здесь (это readOnly-tx + self-invocation = не сработает),
            // а полагаемся на upsert в put() — следующий успешный HTTP
            // перепишет эту строку. Cleanup-cron тоже снесёт её по TTL.
            log.warn("[OVERPASS-PCACHE] Ошибка десериализации key={}: {}. Будет перезаписана при следующем апдейте.",
                    cacheKey, ex.getMessage());
            return Optional.empty();
        }
    }

    @Transactional
    public void put(String cacheKey, OverpassAreaSnapshot snapshot) {
        // FAILED НЕ кэшируем — иначе временный сбой Overpass «прибьёт»
        // точку на 7 дней. Caffeine-аннотация тоже не кэширует FAILED
        // (см. OverpassPlacesService.searchAreaSnapshot unless=...).
        if (snapshot.isFailed()) return;
        try {
            String json = objectMapper.writeValueAsString(snapshot);
            // Upsert: на существующий ключ обновляем запись (новый cachedAt).
            // Делаем через find+save вместо native ON CONFLICT, чтобы не
            // зависеть от диалекта.
            Optional<OverpassCacheEntry> existing = repository.findByCacheKey(cacheKey);
            OverpassCacheEntry entry = existing.orElseGet(() -> OverpassCacheEntry.builder()
                    .cacheKey(cacheKey)
                    .build());
            entry.setResponseJson(json);
            entry.setCachedAt(LocalDateTime.now());
            repository.save(entry);
        } catch (Exception ex) {
            log.warn("[OVERPASS-PCACHE] Ошибка сохранения key={}: {}", cacheKey, ex.getMessage());
        }
    }

    /**
     * Раз в сутки удаляем просроченные записи. Без cleanup'a таблица растёт
     * неограниченно (новые точки/радиусы дают новые cache key).
     */
    @Scheduled(cron = "0 0 3 * * *")
    @Transactional
    public void cleanupExpired() {
        LocalDateTime cutoff = LocalDateTime.now().minusHours(ttlHours);
        int removed = repository.deleteByCachedAtBefore(cutoff);
        if (removed > 0) {
            log.info("[OVERPASS-PCACHE] Удалено {} устаревших записей (старше {} ч)", removed, ttlHours);
        }
    }
}
