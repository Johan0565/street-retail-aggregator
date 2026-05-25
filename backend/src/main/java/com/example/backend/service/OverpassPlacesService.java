package com.example.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Клиент Overpass API (OpenStreetMap). Один запрос на помещение возвращает
 * и коммерческие POI, и узлы общественного транспорта вокруг точки —
 * раньше делалось двумя независимыми HTTP-вызовами, теперь объединено
 * в {@link #searchAreaSnapshot(double, double, int)}.
 *
 * Особенности реализации:
 *   - <b>Multi-mirror.</b> Список зеркал берём из {@code overpass.api.urls}
 *     (CSV). При сбое первого пробуем следующее: публичные миррoры
 *     overpass-api.de, overpass.kumi.systems, overpass.private.coffee
 *     ходят к одному и тому же снапшоту OSM, но независимы по доступности.
 *     Это устраняет ключевой источник «empty result → max score» при
 *     даунтайме главного эндпоинта.
 *   - <b>Retry с exp-backoff внутри одного mirror'a.</b> Один транзиентный
 *     5xx — это норма для бесплатного Overpass; ретраим 2 раза, потом
 *     переходим к следующему mirror'у.
 *   - <b>FetchStatus в ответе.</b> {@link OverpassAreaSnapshot} различает
 *     «API ответил, элементов 0» (OK — рядом действительно ничего нет) и
 *     «все mirror'ы упали» (FAILED — данных нет, скоринг должен это
 *     учитывать, а не считать «нет конкурентов = 40/40»).
 *   - <b>Кэширование.</b> Spring {@code @Cacheable} по бакетированным
 *     координатам и радиусу; {@code unless} НЕ кэширует FAILED, чтобы
 *     временный сбой Overpass не «прибил» точку на час.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class OverpassPlacesService {

    /**
     * OSM-теги, которые формируют «рубрику» бизнеса.
     */
    private static final List<String> CATEGORY_KEYS = List.of(
            "shop", "amenity", "office", "healthcare", "leisure", "craft", "tourism");

    private static final List<String> AMENITY_VALUES = List.of(
            "pharmacy", "cafe", "restaurant", "fast_food", "bar", "pub", "nightclub",
            "bank", "atm", "post_office", "clinic", "doctors", "dentist", "veterinary",
            "kindergarten", "school", "college", "university", "language_school",
            "driving_school", "training", "cinema", "theatre", "library",
            "food_court", "ice_cream", "biergarten", "parcel_locker", "post_depot");

    private static final List<String> LEISURE_VALUES = List.of(
            "fitness_centre", "sports_centre", "dance", "playground");

    private static final List<String> HEALTHCARE_VALUES = List.of(
            "clinic", "doctor", "pharmacy", "dentist", "centre", "hospital",
            "optometrist", "cosmetic_surgery");

    private static final List<String> OFFICE_VALUES = List.of(
            "travel_agent", "estate_agent", "company", "educational_institution",
            "financial", "insurance", "courier");

    private static final List<String> TOURISM_VALUES = List.of(
            "hotel", "hostel", "guest_house", "information");

    /** Сколько раз повторить запрос к одному mirror'у перед переходом к следующему. */
    private static final int MAX_ATTEMPTS_PER_MIRROR = 2;
    /** База exp-backoff между попытками: 500мс, 1000мс. */
    private static final long BACKOFF_BASE_MS = 500;

    @Value("${overpass.api.urls:${overpass.api.url:https://overpass-api.de/api/interpreter}}")
    private String overpassUrlsCsv;

    private final ObjectMapper objectMapper;
    private final RestClient overpassRestClient;
    private final OverpassPersistentCache persistentCache;

    private List<String> mirrors;

    @PostConstruct
    void initMirrors() {
        mirrors = new ArrayList<>();
        for (String raw : overpassUrlsCsv.split(",")) {
            String url = raw.trim();
            if (!url.isEmpty()) mirrors.add(url);
        }
        if (mirrors.isEmpty()) {
            mirrors.add("https://overpass-api.de/api/interpreter");
        }
        log.info("[OVERPASS] Сконфигурированы mirror'ы: {}", mirrors);
    }

    // =========================================================================
    //  ПУБЛИЧНЫЙ API
    // =========================================================================

    /**
     * Главный метод: один запрос к Overpass за всеми POI и транспортными
     * узлами вокруг точки. Результат кэшируется (in-memory Caffeine), кроме
     * FAILED — провал не кэшируем, иначе на час «убьём» точку.
     */
    @Cacheable(
            value = "overpassArea",
            key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + " +
                  "T(Math).floorDiv(#radiusMeters, 250)",
            unless = "#result == null || #result.isFailed()"
    )
    public OverpassAreaSnapshot searchAreaSnapshot(double lat, double lon, int radiusMeters) {
        String cacheKey = buildCacheKey(lat, lon, radiusMeters);

        // L2 — постоянный кэш в PostgreSQL. Caffeine (L1) уже миссанул раз
        // мы здесь; теперь проверяем БД, чтобы холодный старт после рестарта
        // backend'a не бил по публичным mirror'ам Overpass.
        var fromDb = persistentCache.get(cacheKey);
        if (fromDb.isPresent()) {
            log.debug("[OVERPASS] DB-cache hit (key={})", cacheKey);
            return fromDb.get();
        }

        String query = buildCombinedQuery(lat, lon, radiusMeters);
        String body = executeWithMirrorFallback(query, lat, lon, radiusMeters);
        if (body == null) {
            // Все mirror'ы упали или таймаут везде. Скорер увидит FAILED
            // и не выдаст ложный max-балл «нет конкурентов = 40/40».
            log.warn("[OVERPASS] Все mirror'ы недоступны (lat={}, lon={}, r={}м)",
                    lat, lon, radiusMeters);
            return OverpassAreaSnapshot.failed();
        }
        OverpassAreaSnapshot parsed = parseCombined(body);
        log.info("[OVERPASS] (lat={}, lon={}, r={}м): получено {} POI + {} транспортных узлов",
                lat, lon, radiusMeters, parsed.businesses().size(), parsed.transportStops().size());

        // Кладём в L2 — следующий рестарт backend'a не потеряет этот результат.
        persistentCache.put(cacheKey, parsed);
        return parsed;
    }

    private String buildCacheKey(double lat, double lon, int radiusMeters) {
        long latKey = Math.round(lat * 1000);
        long lonKey = Math.round(lon * 1000);
        int radiusBucket = Math.floorDiv(radiusMeters, 250);
        return latKey + "_" + lonKey + "_" + radiusBucket;
    }

    /**
     * Совместимость с устаревшим вызовом: возвращает только бизнесы.
     * Внутри идёт через {@link #searchAreaSnapshot}, чтобы кэш был общим.
     */
    public List<NearbyBusiness> searchNearby(double lat, double lon, int radiusMeters) {
        return searchAreaSnapshot(lat, lon, radiusMeters).businesses();
    }

    /**
     * Совместимость с устаревшим вызовом: возвращает только транспорт.
     */
    public List<TransportStop> searchTransportNearby(double lat, double lon, int radiusMeters) {
        return searchAreaSnapshot(lat, lon, radiusMeters).transportStops();
    }

    // =========================================================================
    //  HTTP с multi-mirror fallback и retry
    // =========================================================================

    /**
     * Перебирает mirror'ы по порядку. На каждом — до {@link #MAX_ATTEMPTS_PER_MIRROR}
     * попыток с экспоненциальным backoff. Возвращает тело первого успешного
     * непустого ответа, либо {@code null} если все mirror'ы исчерпаны.
     */
    private String executeWithMirrorFallback(String query, double lat, double lon, int radiusMeters) {
        String formBody = "data=" + URLEncoder.encode(query, StandardCharsets.UTF_8);

        for (int m = 0; m < mirrors.size(); m++) {
            String mirror = mirrors.get(m);
            for (int attempt = 1; attempt <= MAX_ATTEMPTS_PER_MIRROR; attempt++) {
                try {
                    String body = overpassRestClient.post()
                            .uri(mirror)
                            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                            .header("User-Agent", "street-retail-aggregator/1.0 (scoring)")
                            .header("Accept", "application/json")
                            .body(formBody)
                            .retrieve()
                            .body(String.class);

                    if (body != null && !body.isBlank()) {
                        if (m > 0 || attempt > 1) {
                            log.info("[OVERPASS] Успех через mirror[{}]={} (попытка {}) для (lat={}, lon={}, r={}м)",
                                    m, mirror, attempt, lat, lon, radiusMeters);
                        }
                        return body;
                    }
                    log.warn("[OVERPASS] Пустое тело от {} (попытка {}/{}) для (lat={}, lon={}, r={}м)",
                            mirror, attempt, MAX_ATTEMPTS_PER_MIRROR, lat, lon, radiusMeters);
                } catch (Exception e) {
                    log.warn("[OVERPASS] Сбой {} (попытка {}/{}) для (lat={}, lon={}, r={}м): {}",
                            mirror, attempt, MAX_ATTEMPTS_PER_MIRROR, lat, lon, radiusMeters, e.getMessage());
                }
                if (attempt < MAX_ATTEMPTS_PER_MIRROR) {
                    sleepBackoff(attempt);
                }
            }
        }
        return null;
    }

    private void sleepBackoff(int attempt) {
        long delay = BACKOFF_BASE_MS * (1L << (attempt - 1));
        try {
            Thread.sleep(delay);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }

    // =========================================================================
    //  ПОСТРОЕНИЕ ЗАПРОСА: бизнесы + транспорт в одном QL
    // =========================================================================

    /**
     * Один Overpass QL, объединяющий и коммерческие POI, и транспортные узлы.
     * Раньше делалось двумя запросами, что давало два сетевых round-trip'a и
     * две позиции в очереди Overpass на каждое помещение. Теперь — один.
     */
    private String buildCombinedQuery(double lat, double lon, int radiusMeters) {
        String around = "around:" + radiusMeters + "," + lat + "," + lon;
        // timeout:25 — на серверной стороне ограничиваем выполнение запроса
        // 25 секундами. Объединённый запрос тяжелее одиночного — выделяем
        // больше бюджета, но всё равно жёстко режем, иначе stuck-запрос
        // блокирует одну из 8 параллельных нитей.
        StringBuilder q = new StringBuilder("[out:json][timeout:25];(");

        // --- Бизнесы ---
        q.append("nwr[shop](").append(around).append(");");
        q.append("nwr[amenity~\"^(").append(joinAlt(AMENITY_VALUES)).append(")$\"](")
         .append(around).append(");");
        q.append("nwr[office~\"^(").append(joinAlt(OFFICE_VALUES)).append(")$\"](")
         .append(around).append(");");
        q.append("nwr[healthcare~\"^(").append(joinAlt(HEALTHCARE_VALUES)).append(")$\"](")
         .append(around).append(");");
        q.append("nwr[leisure~\"^(").append(joinAlt(LEISURE_VALUES)).append(")$\"](")
         .append(around).append(");");
        q.append("nwr[craft](").append(around).append(");");
        q.append("nwr[tourism~\"^(").append(joinAlt(TOURISM_VALUES)).append(")$\"](")
         .append(around).append(");");

        // --- Транспорт ---
        // С [name] — иначе в OSM Москвы прилетают «технические» ноды (ref=5).
        q.append("nwr[railway=station][name](").append(around).append(");");
        q.append("nwr[railway=subway_entrance][name](").append(around).append(");");
        // tram_stop и bus_stop часто мапятся без name — лучше показать
        // «трамвайная остановка», чем потерять полностью.
        q.append("nwr[railway=tram_stop](").append(around).append(");");
        q.append("nwr[highway=bus_stop](").append(around).append(");");
        q.append("nwr[public_transport=station][name](").append(around).append(");");

        // out tags center N — N hard-cap. 3500 покрывает плотные кварталы
        // (центр Мск, 1.5км) с запасом и под бизнесы, и под транспорт.
        q.append(");out tags center 3500;");
        return q.toString();
    }

    private String joinAlt(List<String> values) {
        return String.join("|", values);
    }

    // =========================================================================
    //  ПАРСИНГ: один проход по elements, разводим в бизнесы и транспорт
    // =========================================================================

    private OverpassAreaSnapshot parseCombined(String body) {
        List<NearbyBusiness> businesses = new ArrayList<>();
        List<TransportStop> transport = new ArrayList<>();
        try {
            JsonNode root = objectMapper.readTree(body);
            JsonNode elements = root.path("elements");
            if (!elements.isArray()) {
                String preview = body.length() > 400 ? body.substring(0, 400) + "…" : body;
                log.warn("[OVERPASS] В ответе нет массива elements. Preview: {}", preview);
                return new OverpassAreaSnapshot(businesses, transport, OverpassAreaSnapshot.FetchStatus.OK);
            }

            // dedup: один OSM-объект может быть и amenity, и building.
            Map<String, NearbyBusiness> businessById = new LinkedHashMap<>();
            Map<String, TransportStop> transportById = new LinkedHashMap<>();

            for (JsonNode el : elements) {
                String type = el.path("type").asText("");
                long id = el.path("id").asLong(0);
                JsonNode tags = el.path("tags");
                if (!tags.isObject()) continue;

                String key = type + ":" + id;
                double[] coords = parseCoords(el);

                // 1) Сначала пробуем как транспортный узел (railway/highway/public_transport).
                //    Транспортные теги не пересекаются с бизнес-тегами в нашем фильтре,
                //    так что одинаковый OSM-объект попадёт ровно в одну категорию.
                TransportStop.TransportType stopType = classifyTransport(tags);
                if (stopType != null) {
                    String name = bestTransportName(tags);
                    if (name == null || name.isBlank()) {
                        name = defaultTransportName(stopType);
                    }
                    transportById.putIfAbsent(key, new TransportStop(name, stopType, coords[0], coords[1]));
                    continue;
                }

                // 2) Иначе классифицируем как бизнес.
                List<String> rubrics = extractRubrics(tags);
                if (rubrics.isEmpty()) continue;
                String name = bestName(tags);
                if (name == null || name.isBlank()) {
                    name = humanizeFallbackName(rubrics.get(0));
                }
                businessById.putIfAbsent(key, new NearbyBusiness(name, rubrics, coords[0], coords[1]));
            }
            businesses.addAll(businessById.values());
            transport.addAll(transportById.values());
        } catch (Exception e) {
            String preview = body.length() > 400 ? body.substring(0, 400) + "…" : body;
            log.warn("[OVERPASS] Ошибка парсинга ответа: {} | preview: {}", e.getMessage(), preview);
            // Парсинг сломался — это сетевой ответ, но битый. Считаем FAILED:
            // лучше пометить «недоступно», чем выдать «нет конкурентов = 40/40».
            return OverpassAreaSnapshot.failed();
        }
        return new OverpassAreaSnapshot(businesses, transport, OverpassAreaSnapshot.FetchStatus.OK);
    }

    private TransportStop.TransportType classifyTransport(JsonNode tags) {
        String railway = textOrEmpty(tags, "railway");
        String station = textOrEmpty(tags, "station");
        String subway  = textOrEmpty(tags, "subway");
        String highway = textOrEmpty(tags, "highway");
        String pt      = textOrEmpty(tags, "public_transport");

        if ("subway_entrance".equals(railway)) return TransportStop.TransportType.METRO;
        if ("station".equals(railway) && ("subway".equals(station) || "yes".equals(subway)))
            return TransportStop.TransportType.METRO;
        if ("station".equals(railway)) return TransportStop.TransportType.RAIL;
        if ("station".equals(pt) && ("subway".equals(station) || "yes".equals(subway)))
            return TransportStop.TransportType.METRO;
        if ("station".equals(pt)) return TransportStop.TransportType.RAIL;
        if ("tram_stop".equals(railway)) return TransportStop.TransportType.TRAM;
        if ("bus_stop".equals(highway)) return TransportStop.TransportType.BUS;
        return null;
    }

    private String textOrEmpty(JsonNode tags, String key) {
        JsonNode v = tags.get(key);
        if (v == null || v.isMissingNode()) return "";
        return v.asText("").trim().toLowerCase();
    }

    private String defaultTransportName(TransportStop.TransportType t) {
        return switch (t) {
            case METRO -> "метро";
            case RAIL  -> "ж/д станция";
            case TRAM  -> "трамвайная остановка";
            case BUS   -> "автобусная остановка";
        };
    }

    private List<String> extractRubrics(JsonNode tags) {
        List<String> rubrics = new ArrayList<>();
        for (String key : CATEGORY_KEYS) {
            JsonNode v = tags.get(key);
            if (v == null || v.isMissingNode()) continue;
            String value = v.asText("").trim().toLowerCase();
            if (value.isEmpty() || "no".equals(value) || "vacant".equals(value)) continue;
            rubrics.add(key + "=" + value);
        }
        return rubrics;
    }

    private String bestName(JsonNode tags) {
        String[] candidates = {"name:ru", "name", "brand", "operator", "official_name", "short_name"};
        for (String c : candidates) {
            JsonNode n = tags.get(c);
            if (n != null && !n.isMissingNode()) {
                String s = n.asText("").trim();
                if (!s.isEmpty()) return s;
            }
        }
        return null;
    }

    /**
     * Имя транспортной остановки. НЕ падает в {@code operator}/{@code brand}/
     * {@code ref}: для метро это даёт «ГУП "Московский метрополитен"» или
     * просто номер линии («5») вместо названия станции.
     */
    private String bestTransportName(JsonNode tags) {
        String[] candidates = {"name:ru", "name", "official_name", "alt_name", "short_name"};
        for (String c : candidates) {
            JsonNode n = tags.get(c);
            if (n != null && !n.isMissingNode()) {
                String s = n.asText("").trim();
                if (!s.isEmpty()) return s;
            }
        }
        return null;
    }

    private String humanizeFallbackName(String rubric) {
        return rubric;
    }

    private double[] parseCoords(JsonNode el) {
        if (el.has("lat") && el.has("lon")) {
            return new double[]{ el.get("lat").asDouble(0), el.get("lon").asDouble(0) };
        }
        JsonNode center = el.path("center");
        if (center.isObject()) {
            return new double[]{ center.path("lat").asDouble(0), center.path("lon").asDouble(0) };
        }
        return new double[]{ 0, 0 };
    }
}
