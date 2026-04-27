package com.example.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Клиент 2GIS Places API.
 * Возвращает список уникальных рубрик организаций в заданном радиусе.
 * Результаты кэшируются на 30 минут (CacheConfig) по округлённым координатам.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class GisSearchService {

    private static final String GIS_API_BASE = "https://catalog.api.2gis.com/3.0/items";
    private static final int MAX_RADIUS = 5000;
    private static final int PAGE_SIZE = 50;

    @Value("${twogis.api.key}")
    private String apiKey;

    private final ObjectMapper objectMapper;
    private final RestClient restClient = RestClient.create();

    /**
     * Возвращает список уникальных рубрик (строчных, нормализованных) в заданном радиусе
     * от точки (lat, lon). Кэш-ключ строится по округлённым до ~111 м координатам.
     *
     * Примечание: 2GIS принимает координаты в порядке lon,lat.
     */
    @Cacheable(
            value = "gisNearby",
            key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + #radiusMeters"
    )
    public List<String> getNearbyRubricNames(double lat, double lon, int radiusMeters) {
        int radius = Math.min(radiusMeters, MAX_RADIUS);
        String url = GIS_API_BASE
                + "?point=" + lon + "," + lat
                + "&radius=" + radius
                + "&type=branch"
                + "&fields=items.rubrics"
                + "&key=" + apiKey
                + "&page_size=" + PAGE_SIZE;

        try {
            String body = restClient.get()
                    .uri(url)
                    .retrieve()
                    .body(String.class);

            return parseRubricNames(body);
        } catch (Exception e) {
            log.warn("2GIS API недоступен (lat={}, lon={}, r={}): {}", lat, lon, radius, e.getMessage());
            return List.of();
        }
    }

    private List<String> parseRubricNames(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            JsonNode items = root.path("result").path("items");

            Set<String> names = new LinkedHashSet<>();
            if (items.isArray()) {
                for (JsonNode item : items) {
                    JsonNode rubrics = item.path("rubrics");
                    if (rubrics.isArray()) {
                        for (JsonNode rubric : rubrics) {
                            String name = rubric.path("name").asText("").trim();
                            if (!name.isEmpty()) {
                                names.add(name.toLowerCase());
                            }
                        }
                    }
                }
            }
            return new ArrayList<>(names);
        } catch (Exception e) {
            log.warn("Ошибка парсинга ответа 2GIS: {}", e.getMessage());
            return List.of();
        }
    }
}
