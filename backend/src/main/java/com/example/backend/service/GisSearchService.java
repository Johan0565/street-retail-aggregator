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
import java.util.List;

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
     * Возвращает список рубрик для каждого заведения в заданном радиусе.
     * Каждый вложенный список — рубрики одного конкретного заведения (branch).
     * Кэш-ключ строится по округлённым до ~111 м координатам.
     *
     * Примечание: 2GIS принимает координаты в порядке lon,lat.
     */
    @Cacheable(
            value = "gisNearby",
            key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + #radiusMeters"
    )
    public List<List<String>> getNearbyRubricNames(double lat, double lon, int radiusMeters) {
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

            List<List<String>> result = parseRubricNames(body);
            log.info("2GIS вернул {} заведений в радиусе {}м (lat={}, lon={})", result.size(), radius, lat, lon);
            if (!result.isEmpty()) {
                log.info("Рубрики первых {} заведений: {}", Math.min(result.size(), 5), result.subList(0, Math.min(result.size(), 5)));
            }
            return result;
        } catch (Exception e) {
            log.warn("2GIS API недоступен (lat={}, lon={}, r={}): {}", lat, lon, radius, e.getMessage());
            return List.of();
        }
    }

    // Возвращает по одному списку рубрик на каждое заведение (не дедуплицирует между заведениями).
    private List<List<String>> parseRubricNames(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            JsonNode items = root.path("result").path("items");

            List<List<String>> perItemRubrics = new ArrayList<>();
            if (items.isArray()) {
                for (JsonNode item : items) {
                    JsonNode rubrics = item.path("rubrics");
                    List<String> itemRubricNames = new ArrayList<>();
                    if (rubrics.isArray()) {
                        for (JsonNode rubric : rubrics) {
                            String name = rubric.path("name").asText("").trim();
                            if (!name.isEmpty()) {
                                itemRubricNames.add(name.toLowerCase());
                            }
                        }
                    }
                    if (!itemRubricNames.isEmpty()) {
                        perItemRubrics.add(itemRubricNames);
                    }
                }
            }
            return perItemRubrics;
        } catch (Exception e) {
            log.warn("Ошибка парсинга ответа 2GIS: {}", e.getMessage());
            return List.of();
        }
    }
}
