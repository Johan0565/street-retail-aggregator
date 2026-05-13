package com.example.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Клиент 2GIS Catalog API для справочника рубрик.
 *
 * Фетчит каталог рубрик 2GIS один раз при первом обращении (lazy + cached в памяти).
 * Используется для автоматического заполнения BusinessCategory.twoGisKeywords:
 * берём seed-ключевые слова, находим все 2GIS-рубрики, чьи имена их содержат,
 * и сохраняем канонические имена рубрик как twoGisKeywords. При появлении в 2GIS
 * новой рубрики она автоматически подхватится при следующем перезапуске.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class GisRubricCatalogService {

    private static final String RUBRIC_LIST_URL = "https://catalog.api.2gis.com/2.0/catalog/rubric/list";
    private static final int PAGE_SIZE = 50;
    private static final int MAX_PAGES = 50;

    @Value("${twogis.api.key}")
    private String apiKey;

    @Value("${twogis.region.id:1}") // 1 = Москва по умолчанию
    private int regionId;

    private final ObjectMapper objectMapper;
    private final RestClient gisRestClient;

    private volatile List<RubricItem> cachedRubrics;
    private volatile boolean loadAttempted = false;

    public record RubricItem(String id, String name, String parentId) {}

    /**
     * По набору seed-слов возвращает канонические имена 2GIS-рубрик,
     * чьи имена содержат хотя бы одно из seed-слов. Если каталог
     * недоступен — пустой список (вызывающий код решает, что делать).
     */
    public List<String> expandKeywords(Iterable<String> seedKeywords) {
        List<RubricItem> rubrics = loadCatalog();
        if (rubrics.isEmpty()) return List.of();

        Set<String> result = new LinkedHashSet<>();
        for (String seed : seedKeywords) {
            if (seed == null) continue;
            String lo = seed.trim().toLowerCase();
            if (lo.isEmpty()) continue;
            for (RubricItem r : rubrics) {
                if (r.name().toLowerCase().contains(lo)) {
                    result.add(r.name().toLowerCase());
                }
            }
        }
        return new ArrayList<>(result);
    }

    /** Удобный вариант: принимает CSV-строку seed-keywords. */
    public List<String> expandKeywords(String csvSeeds) {
        if (csvSeeds == null || csvSeeds.isBlank()) return List.of();
        return expandKeywords(Arrays.asList(csvSeeds.split(",")));
    }

    // -------------------------------------------------------------------------

    private synchronized List<RubricItem> loadCatalog() {
        if (cachedRubrics != null) return cachedRubrics;
        if (loadAttempted) return List.of(); // не повторяем при сбое
        loadAttempted = true;

        try {
            List<RubricItem> all = new ArrayList<>();
            int page = 1;
            int totalPages = 1;

            do {
                String url = RUBRIC_LIST_URL
                        + "?region_id=" + regionId
                        + "&fields=items.parent_id"
                        + "&page_size=" + PAGE_SIZE
                        + "&page=" + page
                        + "&key=" + apiKey;

                String body = gisRestClient.get().uri(url).retrieve().body(String.class);
                if (body == null) break;

                JsonNode root = objectMapper.readTree(body);
                int total = root.path("result").path("total").asInt(0);
                totalPages = (int) Math.ceil((double) total / PAGE_SIZE);

                JsonNode items = root.path("result").path("items");
                if (items.isArray()) {
                    for (JsonNode it : items) {
                        String id   = it.path("id").asText("");
                        String name = it.path("name").asText("");
                        String pid  = it.path("parent_id").asText("");
                        if (!id.isEmpty() && !name.isEmpty()) {
                            all.add(new RubricItem(id, name, pid));
                        }
                    }
                }

                page++;
            } while (page <= totalPages && page <= MAX_PAGES);

            log.info("[2GIS-RUBRICS] Загружено {} рубрик из 2GIS (region={})", all.size(), regionId);
            cachedRubrics = all;
            return all;

        } catch (Exception e) {
            log.warn("[2GIS-RUBRICS] Не удалось загрузить каталог рубрик: {}. Используется ручной seed.", e.getMessage());
            cachedRubrics = List.of();
            return List.of();
        }
    }
}
