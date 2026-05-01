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
 * Возвращает список заведений (название + рубрики) в заданном радиусе.
 * Результаты кэшируются по округлённым координатам.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class GisSearchService {

    private static final String GIS_API_BASE = "https://catalog.api.2gis.com/3.0/items";
    private static final int MAX_RADIUS = 5000;
    private static final int PAGE_SIZE = 10;  // 2GIS API limit: 1..10
    private static final int MAX_PAGES = 20;  // 10×20=200 заведений максимум

    @Value("${twogis.api.key}")
    private String apiKey;

    private final ObjectMapper objectMapper;
    private final RestClient gisRestClient;

    @Cacheable(
            value = "gisNearby",
            key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + #radiusMeters",
            unless = "#result == null || #result.isEmpty()"
    )
    public List<NearbyBusiness> getNearbyBusinesses(double lat, double lon, int radiusMeters) {
        int radius = Math.min(radiusMeters, MAX_RADIUS);
        List<NearbyBusiness> all = new ArrayList<>();
        int page = 1;
        int totalPages = 1;

        do {
            String body = fetchPage(lat, lon, radius, page);
            if (body == null) break;

            try {
                JsonNode root = objectMapper.readTree(body);
                int total = root.path("result").path("total").asInt(0);
                totalPages = (int) Math.ceil((double) total / PAGE_SIZE);

                List<NearbyBusiness> pageBusinesses = parseBusinesses(root);
                all.addAll(pageBusinesses);
                log.debug("2GIS страница {}/{}: получено {} заведений (total={})", page, totalPages, pageBusinesses.size(), total);
            } catch (Exception e) {
                log.warn("Ошибка парсинга страницы {} 2GIS (lat={}, lon={}): {}", page, lat, lon, e.getMessage());
                break;
            }

            if (page >= MAX_PAGES) break;
            page++;
        } while (page <= totalPages);

        log.info("2GIS итого: {} заведений в радиусе {}м (lat={}, lon={})", all.size(), radius, lat, lon);
        return all;
    }

    private String fetchPage(double lat, double lon, int radius, int page) {
        String url = GIS_API_BASE
                + "?point=" + lon + "," + lat
                + "&radius=" + radius
                + "&type=branch"
                + "&fields=items.rubrics,items.name_ex"
                + "&key=" + apiKey
                + "&page_size=" + PAGE_SIZE
                + "&page=" + page;

        log.debug("[2GIS-RAW] Запрос URL: {}", url.replace(apiKey, "***KEY***"));

        try {
            String body = gisRestClient.get()
                    .uri(url)
                    .retrieve()
                    .body(String.class);

            if (body == null) {
                log.warn("[2GIS-RAW] Ответ null (lat={}, lon={}, page={})", lat, lon, page);
                return null;
            }
            return body;
        } catch (Exception e) {
            log.warn("2GIS API недоступен на странице {} (lat={}, lon={}, r={}): {}", page, lat, lon, radius, e.getMessage());
            return null;
        }
    }

    private List<NearbyBusiness> parseBusinesses(JsonNode root) {
        JsonNode items = root.path("result").path("items");
        List<NearbyBusiness> result = new ArrayList<>();
        if (!items.isArray()) return result;

        for (JsonNode item : items) {
            // Извлекаем название заведения
            String name = item.path("name_ex").path("primary").asText("").trim();
            if (name.isEmpty()) name = item.path("name").asText("").trim();

            // Извлекаем рубрики
            List<String> rubricNames = new ArrayList<>();
            JsonNode rubrics = item.path("rubrics");
            if (rubrics.isArray()) {
                for (JsonNode rubric : rubrics) {
                    String rubricName = rubric.path("name").asText("").trim();
                    if (!rubricName.isEmpty()) rubricNames.add(rubricName.toLowerCase());
                }
            }

            if (rubricNames.isEmpty()) continue;

            // Если имя пустое — используем первую рубрику как fallback
            if (name.isEmpty()) name = rubricNames.get(0);

            result.add(new NearbyBusiness(name, rubricNames));
        }
        return result;
    }
}
