package com.example.backend.config;

import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.caffeine.CaffeineCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.TimeUnit;

/**
 * In-memory кэши (Caffeine):
 *   - {@code overpassArea} — объединённый ответ Overpass (POI + транспорт).
 *     Это «горячий» слой: типичные точки переоткрываются за минуты,
 *     promax уже в памяти.
 *   - {@code propertyScore} — короткоживущий кэш Score-DTO в рамках одного
 *     прогона батча (saved snapshot в БД — отдельный, долгоживущий слой,
 *     см. PropertyScoreSnapshot).
 *
 * Долгоживущий слой (per-restart) реализован отдельно в PostgreSQL
 * (OverpassCacheEntry, PropertyScoreSnapshot) — Caffeine только для
 * микросекундного доступа в пределах одной JVM-сессии.
 */
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public CacheManager cacheManager() {
        CaffeineCacheManager manager = new CaffeineCacheManager("overpassArea", "propertyScore");
        manager.setCaffeine(Caffeine.newBuilder()
                .expireAfterWrite(60, TimeUnit.MINUTES)
                .maximumSize(2000));
        return manager;
    }
}
