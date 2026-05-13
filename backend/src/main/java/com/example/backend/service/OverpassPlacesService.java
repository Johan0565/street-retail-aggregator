package com.example.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
 * Клиент Overpass API (OpenStreetMap). Возвращает все организации в радиусе
 * вокруг точки одним запросом — никаких ключевых слов и платных квот.
 *
 * Поведение:
 *   - один Overpass-запрос охватывает все retail/service OSM-теги
 *     (shop=*, amenity in (...), office in (...), healthcare in (...),
 *      leisure in (fitness_centre, sports_centre)),
 *   - на выходе — {@link NearbyBusiness} с «рубриками» в формате "key=value"
 *     (например "amenity=pharmacy", "shop=bakery"). Сопоставление с
 *     {@link com.example.backend.entity.BusinessCategory} идёт по этим
 *     парам, без морфологии — OSM-теги уже канонические.
 *
 * HTTP — POST application/x-www-form-urlencoded с полем data, как в
 * официальных примерах. GET-вариант ломался в Spring RestClient из-за
 * повторного percent-экранирования уже закодированной строки.
 *
 * Кэширование — по (округлённые координаты, радиус-бакет). Пустой ответ
 * НЕ кэшируется (unless), чтобы временный сбой Overpass не «прибил» точку
 * на час.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class OverpassPlacesService {

    /**
     * OSM-теги, которые формируют «рубрику» бизнеса. Порядок важен только
     * для логов: shop=* как правило самый специфичный.
     */
    private static final List<String> CATEGORY_KEYS = List.of(
            "shop", "amenity", "office", "healthcare", "leisure", "craft", "tourism");

    /**
     * Значения amenity, которые мы считаем коммерческими организациями.
     * Прочее (parking, bench, fountain и т.п.) отбрасываем, чтобы не
     * тащить из OSM мусор.
     */
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

    @Value("${overpass.api.url:https://overpass-api.de/api/interpreter}")
    private String overpassUrl;

    private final ObjectMapper objectMapper;
    private final RestClient overpassRestClient;

    /**
     * Одно обращение к Overpass возвращает все организации в радиусе.
     * Внутри одного скоринга помещения этот метод вызывается ровно один раз.
     */
    @Cacheable(
            value = "overpassNearby",
            key = "T(Math).round(#lat * 1000) + '_' + T(Math).round(#lon * 1000) + '_' + " +
                  "T(Math).floorDiv(#radiusMeters, 250)",
            unless = "#result == null || #result.isEmpty()"
    )
    public List<NearbyBusiness> searchNearby(double lat, double lon, int radiusMeters) {
        String query = buildQuery(lat, lon, radiusMeters);
        log.info("[OVERPASS] POST {} | query: {}", overpassUrl, query);

        String formBody = "data=" + URLEncoder.encode(query, StandardCharsets.UTF_8);

        String body;
        try {
            body = overpassRestClient.post()
                    .uri(overpassUrl)
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .header("User-Agent", "street-retail-aggregator/1.0 (scoring)")
                    .header("Accept", "application/json")
                    .body(formBody)
                    .retrieve()
                    .body(String.class);
        } catch (Exception e) {
            log.warn("[OVERPASS] Сбой запроса (lat={}, lon={}, r={}м): {}",
                    lat, lon, radiusMeters, e.getMessage());
            return List.of();
        }
        if (body == null || body.isBlank()) {
            log.warn("[OVERPASS] Пустой ответ (lat={}, lon={}, r={}м)", lat, lon, radiusMeters);
            return List.of();
        }

        List<NearbyBusiness> all = parseElements(body);
        log.info("[OVERPASS] (lat={}, lon={}, r={}м): получено {} организаций (тело ответа {} б)",
                lat, lon, radiusMeters, all.size(), body.length());
        return all;
    }

    // =========================================================================

    /**
     * Собирает Overpass QL. Используем {@code nwr} (node/way/relation) с
     * {@code around:}-фильтром — он одинаково ловит точечные и полигональные
     * объекты, а коммерческие помещения в OSM встречаются и как nodes,
     * и как ways (контур здания/арендатор).
     */
    private String buildQuery(double lat, double lon, int radiusMeters) {
        String around = "around:" + radiusMeters + "," + lat + "," + lon;
        StringBuilder q = new StringBuilder("[out:json][timeout:25];(");

        // shop=* — берём всё (теги магазинов уже коммерческие по определению)
        q.append("nwr[shop](").append(around).append(");");

        // amenity — только белый список «организаций»
        q.append("nwr[amenity~\"^(").append(joinAlt(AMENITY_VALUES)).append(")$\"](")
         .append(around).append(");");

        // office — только релевантные клиенту виды
        q.append("nwr[office~\"^(").append(joinAlt(OFFICE_VALUES)).append(")$\"](")
         .append(around).append(");");

        // healthcare — медучреждения вне amenity
        q.append("nwr[healthcare~\"^(").append(joinAlt(HEALTHCARE_VALUES)).append(")$\"](")
         .append(around).append(");");

        // leisure — фитнес/спорт
        q.append("nwr[leisure~\"^(").append(joinAlt(LEISURE_VALUES)).append(")$\"](")
         .append(around).append(");");

        // craft — ремесленные услуги (часто tagged для барбершопов, ателье)
        q.append("nwr[craft](").append(around).append(");");

        // tourism — отели/хостелы (могут быть синергическим соседом)
        q.append("nwr[tourism~\"^(").append(joinAlt(TOURISM_VALUES)).append(")$\"](")
         .append(around).append(");");

        // out tags center N — N это hard-cap на число элементов в ответе.
        // В центре Москвы 1 км легко даёт 500+ организаций, поэтому ставим
        // запас: 3000 покрывает плотные кварталы без обрезания.
        q.append(");out tags center 3000;");
        return q.toString();
    }

    private String joinAlt(List<String> values) {
        return String.join("|", values);
    }

    private List<NearbyBusiness> parseElements(String body) {
        List<NearbyBusiness> out = new ArrayList<>();
        try {
            JsonNode root = objectMapper.readTree(body);
            JsonNode elements = root.path("elements");
            if (!elements.isArray()) {
                String preview = body.length() > 400 ? body.substring(0, 400) + "…" : body;
                log.warn("[OVERPASS] В ответе нет массива elements. Preview: {}", preview);
                return out;
            }

            // dedup: иногда один и тот же объект помечен и amenity, и building,
            // OSM ID уникален в пределах типа элемента (node/way/relation).
            Map<String, NearbyBusiness> byId = new LinkedHashMap<>();

            for (JsonNode el : elements) {
                String type = el.path("type").asText("");
                long id = el.path("id").asLong(0);
                JsonNode tags = el.path("tags");
                if (!tags.isObject()) continue;

                List<String> rubrics = extractRubrics(tags);
                if (rubrics.isEmpty()) continue;

                String name = bestName(tags);
                if (name == null || name.isBlank()) {
                    name = humanizeFallbackName(rubrics.get(0));
                }

                double[] coords = parseCoords(el);

                String key = type + ":" + id;
                byId.putIfAbsent(key, new NearbyBusiness(name, rubrics, coords[0], coords[1]));
            }
            out.addAll(byId.values());
        } catch (Exception e) {
            String preview = body.length() > 400 ? body.substring(0, 400) + "…" : body;
            log.warn("[OVERPASS] Ошибка парсинга ответа: {} | preview: {}", e.getMessage(), preview);
        }
        return out;
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
        // Приоритет — русское имя для UI/AI-объяснений
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

    private String humanizeFallbackName(String rubric) {
        return rubric;
    }

    private double[] parseCoords(JsonNode el) {
        // node — поля lat/lon на верхнем уровне; way/relation — center.lat/lon
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
