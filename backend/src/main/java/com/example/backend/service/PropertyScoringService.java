package com.example.backend.service;

import com.example.backend.dto.ScoreBreakdown;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.Property;
import com.example.backend.entity.SearchProfile;
import com.example.backend.repository.BusinessCategoryRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.ForkJoinPool;
import java.util.stream.Collectors;

/**
 * Скоринг помещений по пяти компонентам (итого 0–100 баллов):
 *
 *   Финансовый мэтч   0–20  — площадь и бюджет, асимметричная гладкая функция
 *   Технический мэтч  0–20  — градиентные штрафы за дефицит мощности/потолков,
 *                              half-penalty при null-полях landlord'a
 *   Конкуренты        0–40  — прямые конкуренты в радиусе через Overpass API,
 *                              distance-weighted exp decay
 *   Синергия          0–15  — соседство с желаемыми категориями, distance-aware,
 *                              насыщающаяся сумма весов (количество соседей даёт прирост)
 *   Транспорт         0–5   — близость общественного транспорта (метро ценнее
 *                              автобуса), distance-weighted exp decay
 *
 * Источник данных о соседях — OpenStreetMap через Overpass API, один
 * объединённый запрос на помещение возвращает и POI, и транспортные узлы
 * (раньше делалось двумя независимыми вызовами).
 *
 * <b>Важное изменение:</b> при FAILED-статусе Overpass-ответа (все mirror'ы
 * упали) НЕ выставляется max-балл «нет конкурентов = 40/40». Вместо этого
 * dataStatus = OVERPASS_UNAVAILABLE, totalScore считается только по
 * финансам+технике, фронт показывает «частичная оценка». Это устраняет
 * ложно-положительные оценки при сбое API.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class PropertyScoringService {

    /**
     * Версия алгоритма скоринга. ОБЯЗАТЕЛЬНО инкрементить при изменении
     * любой формулы или константы ниже — это инвалидирует все сохранённые
     * snapshot'ы в БД и форсирует их пересчёт. Без этого после деплоя
     * пользователи продолжат видеть оценки, посчитанные по старой формуле.
     */
    public static final String ALGORITHM_VERSION = "v2.0";

    private final OverpassPlacesService overpassPlacesService;
    private final BusinessCategoryRepository businessCategoryRepository;

    private static final int MAX_FINANCIAL_SCORE   = 20;
    private static final int MAX_TECHNICAL_SCORE   = 20;
    private static final int MAX_COMPETITOR_SCORE  = 40;
    private static final int MAX_SYNERGY_SCORE     = 15;
    private static final int MAX_TRANSPORT_SCORE   = 5;

    // --- Транспорт: характерная пешеходная дистанция ---
    private static final double TRANSPORT_SIGMA_METERS = 500.0;
    // Радиус поиска транспорта фиксирован: бизнес-радиус арендатора может быть
    // мал (например 300м), а ближайшая станция — в 800м. Для UX важнее знать
    // «есть ли метро поблизости вообще», чем рассчитывать строго по фильтру.
    private static final int TRANSPORT_SEARCH_RADIUS_METERS = 1500;

    // --- Финансовый блок: half / half между бюджетом и площадью ---
    private static final double BUDGET_AXIS_MAX = 10.0;
    private static final double AREA_AXIS_MAX   = 10.0;
    private static final double BUDGET_OVER_DECAY = 3.0;
    private static final double AREA_UNDER_DECAY  = 4.0;
    private static final double AREA_OVER_DECAY   = 1.5;

    // --- Технический блок ---
    private static final double UNKNOWN_FIELD_PENALTY_FACTOR = 0.5;
    private static final double CEILING_FULL_PENALTY_DEFICIT_M = 0.3;

    // --- Параметры алгоритма distance-aware скоринга соседей ---
    private static final double DISTANCE_SIGMA_DIVISOR = 3.0;
    private static final double COMPETITOR_DECAY_K_DIRECT   = 1.0;
    private static final double FALLBACK_WEIGHT_MISSING_COORDS = 0.2;
    private static final double EARTH_RADIUS_METERS = 6_371_000.0;

    // --- Синергия: насыщающаяся сумма весов на категорию ---
    private static final double SYNERGY_SATURATION_K = 0.7;

    // =========================================================================
    //  ПУБЛИЧНЫЕ МЕТОДЫ
    // =========================================================================

    public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
        List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
        Map<String, List<BusinessCategory>> tagIndex = buildTagIndex(allCategories);

        // Принудительно инициализируем lazy-ассоциации профиля до выхода
        // в параллельный пул — параллельные треды могут не иметь Hibernate
        // session-а от OSIV, что выльется в LazyInitializationException.
        if (profile.getBusinessCategory() != null) profile.getBusinessCategory().getName();
        if (profile.getDesiredNeighbors() != null) profile.getDesiredNeighbors().size();
        properties.forEach(p -> { if (p.getImages() != null) p.getImages().size(); });

        // Параллелим Overpass-вызовы между объектами. 8 потоков — компромисс
        // между wall-clock временем и нагрузкой на Overpass.
        ForkJoinPool pool = new ForkJoinPool(8);
        try {
            return pool.submit(() -> properties.parallelStream()
                    .map(p -> scoreInternal(profile, p, tagIndex))
                    .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
                    .collect(Collectors.toList())
            ).join();
        } finally {
            pool.shutdown();
        }
    }

    public ScoredPropertyDto scorePropertyWithGis(SearchProfile profile, Property property) {
        List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
        Map<String, List<BusinessCategory>> tagIndex = buildTagIndex(allCategories);
        return scoreInternal(profile, property, tagIndex);
    }

    // =========================================================================
    //  ЕДИНЫЙ ВНУТРЕННИЙ SCORER
    // =========================================================================

    private ScoredPropertyDto scoreInternal(SearchProfile profile, Property property,
                                             Map<String, List<BusinessCategory>> tagIndex) {
        FinancialResult financial = calculateFinancial(profile, property);
        TechnicalResult technical = calculateTechnical(profile, property);

        // Один объединённый Overpass-вызов за всеми соседями И транспортом —
        // раньше было два независимых HTTP-запроса с параллельной отправкой.
        // Теперь — один round-trip и одна позиция в очереди Overpass на
        // помещение, плюс общая обёртка multi-mirror+retry.
        OverpassAreaSnapshot snapshot = fetchAreaSnapshot(profile, property);

        ScoredPropertyDto.DataStatus dataStatus = snapshot.isFailed()
                ? ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE
                : ScoredPropertyDto.DataStatus.COMPLETE;

        NeighborhoodResult neighborhood = analyzeNeighborhood(profile, property, tagIndex, snapshot);
        TransportResult transport = calculateTransport(property, snapshot);

        int total;
        String label;
        String color;
        if (dataStatus == ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE) {
            // Считаем только то, что реально посчитано. Раньше тут было
            // 40+15+5 = 60 «бесплатных» баллов при сбое Overpass, и плохой
            // адрес выглядел отличным мэтчем. Теперь — честные fin+tech.
            total = financial.score() + technical.score();
            label = "⚠️ Частичная оценка — попробуйте позже";
            color = "gray";
        } else {
            total = financial.score() + technical.score()
                  + neighborhood.competitorScore() + neighborhood.synergyScore()
                  + transport.score();
            label = resolveMatchLabel(total);
            color = resolveMatchColor(total);
        }

        log.debug("Scoring [{}]: total={}, fin={}, tech={}, comp={}, syn={}, trans={}, status={}",
                property.getId(), total, financial.score(), technical.score(),
                neighborhood.competitorScore(), neighborhood.synergyScore(), transport.score(), dataStatus);

        ScoreBreakdown breakdown = ScoreBreakdown.builder()
                .financial(financial.part())
                .technical(technical.part())
                .competitor(neighborhood.competitorPart())
                .synergy(neighborhood.synergyPart())
                .transport(transport.part())
                .build();

        return ScoredPropertyDto.builder()
                .property(property)
                .totalScore(total)
                .financialScore(financial.score())
                .technicalScore(technical.score())
                .competitorScore(neighborhood.competitorScore())
                .synergyScore(neighborhood.synergyScore())
                .transportScore(transport.score())
                .directCompetitorNames(neighborhood.directNames())
                .synergyNeighborNames(neighborhood.synergyNames())
                .matchLabel(label)
                .matchColor(color)
                .breakdown(breakdown)
                .dataStatus(dataStatus)
                .algorithmVersion(ALGORITHM_VERSION)
                .build();
    }

    /**
     * Объединяет радиусы из профиля и фиксированный транспортный радиус,
     * вызывает один Overpass-запрос. Если у помещения нет координат —
     * возвращает «пустой OK» снимок (это валидное состояние, скоринг
     * сам обработает отсутствие координат корректно).
     */
    private OverpassAreaSnapshot fetchAreaSnapshot(SearchProfile profile, Property property) {
        if (property.getLatitude() == null || property.getLongitude() == null) {
            return new OverpassAreaSnapshot(List.of(), List.of(), OverpassAreaSnapshot.FetchStatus.OK);
        }
        int competitorRadius = profile.getSearchRadiusMeters() != null
                ? Math.min(profile.getSearchRadiusMeters(), 5000)
                : 1000;
        int synergyRadius = profile.getSynergyRadiusMeters() != null
                ? Math.min(profile.getSynergyRadiusMeters(), 5000)
                : competitorRadius;
        // Один запрос за всем: бизнесы хотят бóльший из competitor/synergy,
        // транспорт — отдельный фиксированный 1500м. Берём общий max.
        int radius = Math.max(Math.max(competitorRadius, synergyRadius), TRANSPORT_SEARCH_RADIUS_METERS);
        return overpassPlacesService.searchAreaSnapshot(
                property.getLatitude().doubleValue(),
                property.getLongitude().doubleValue(),
                radius);
    }

    private record FinancialResult(int score, ScoreBreakdown.FinancialPart part) {}
    private record TechnicalResult(int score, ScoreBreakdown.TechnicalPart part) {}
    private record TransportResult(int score, ScoreBreakdown.TransportPart part) {}

    // =========================================================================
    //  КОМПОНЕНТ 1: Финансовый мэтч (0–20 баллов)
    // =========================================================================

    private FinancialResult calculateFinancial(SearchProfile profile, Property property) {
        BudgetEval b = evalBudget(profile, property);
        AreaEval a = evalArea(profile, property);
        int total = Math.max(0, Math.min((int) Math.round(b.points + a.points), MAX_FINANCIAL_SCORE));
        ScoreBreakdown.FinancialPart part = ScoreBreakdown.FinancialPart.builder()
                .budgetPoints(round1(b.points))
                .budgetReason(b.reason)
                .areaPoints(round1(a.points))
                .areaReason(a.reason)
                .build();
        return new FinancialResult(total, part);
    }

    private record BudgetEval(double points, String reason) {}
    private record AreaEval(double points, String reason) {}

    private BudgetEval evalBudget(SearchProfile profile, Property property) {
        BigDecimal price = property.getPricePerMonth();
        if (price == null) return new BudgetEval(0.0, "цена не указана");
        BigDecimal max = profile.getMaxBudget();
        BigDecimal min = profile.getMinBudget();
        if (max == null || price.compareTo(max) <= 0) {
            if (min != null && price.compareTo(min) < 0) {
                return new BudgetEval(BUDGET_AXIS_MAX, "цена " + price + " ₽/мес ниже минимума " + min + " — это плюс");
            }
            return new BudgetEval(BUDGET_AXIS_MAX, "цена " + price + " ₽/мес в бюджете");
        }
        double overRatio = price.subtract(max).doubleValue() / max.doubleValue();
        double points = BUDGET_AXIS_MAX * Math.exp(-BUDGET_OVER_DECAY * overRatio);
        return new BudgetEval(points,
                String.format("цена %s ₽/мес выше max %s на %.0f%%", price, max, overRatio * 100));
    }

    private AreaEval evalArea(SearchProfile profile, Property property) {
        BigDecimal area = property.getAreaSqm();
        if (area == null) return new AreaEval(0.0, "площадь не указана");
        BigDecimal min = profile.getMinArea();
        BigDecimal max = profile.getMaxArea();
        if (min != null && area.compareTo(min) < 0) {
            double deficit = min.subtract(area).doubleValue() / min.doubleValue();
            double points = AREA_AXIS_MAX * Math.exp(-AREA_UNDER_DECAY * deficit);
            return new AreaEval(points,
                    String.format("площадь %s м² меньше min %s на %.0f%%", area, min, deficit * 100));
        }
        if (max != null && area.compareTo(max) > 0) {
            double overRatio = area.subtract(max).doubleValue() / max.doubleValue();
            double points = AREA_AXIS_MAX * Math.exp(-AREA_OVER_DECAY * overRatio);
            return new AreaEval(points,
                    String.format("площадь %s м² больше max %s на %.0f%%", area, max, overRatio * 100));
        }
        return new AreaEval(AREA_AXIS_MAX, "площадь " + area + " м² в диапазоне");
    }

    // =========================================================================
    //  КОМПОНЕНТ 2: Технический мэтч (0–20 баллов)
    // =========================================================================

    private TechnicalResult calculateTechnical(SearchProfile profile, Property property) {
        List<ScoreBreakdown.TechnicalItem> items = new ArrayList<>();
        double score = MAX_TECHNICAL_SCORE;

        score -= addBoolItem(items, "вода",            profile.getRequiresWater(),            property.getHasWater(),            4);
        score -= addBoolItem(items, "вытяжка",         profile.getRequiresVentilation(),      property.getHasVentilation(),      4);
        score -= addBoolItem(items, "отдельный вход",  profile.getRequiresSeparateEntrance(), property.getHasSeparateEntrance(), 3);
        score -= addBoolItem(items, "санузел",         profile.getRequiresWc(),               property.getHasWc(),               3);
        score -= addBoolItem(items, "парковка",        profile.getRequiresParking(),          property.getHasParking(),          2);
        score -= addBoolItem(items, "зона разгрузки",  profile.getRequiresLoadingZone(),      property.getHasLoadingZone(),      2);
        score -= addPowerItem(items, profile.getMinPowerKw(), property.getPowerKw());
        score -= addCeilingItem(items, profile.getMinCeilingHeight(), property.getCeilingHeight());

        int total = (int) Math.round(Math.max(0, score));
        ScoreBreakdown.TechnicalPart part = ScoreBreakdown.TechnicalPart.builder()
                .items(items)
                .build();
        return new TechnicalResult(total, part);
    }

    private double addBoolItem(List<ScoreBreakdown.TechnicalItem> items, String label,
                               Boolean required, Boolean actual, double full) {
        if (!Boolean.TRUE.equals(required)) return 0;
        double penalty;
        String reason;
        if (Boolean.TRUE.equals(actual)) {
            return 0;
        } else if (actual == null) {
            penalty = full * UNKNOWN_FIELD_PENALTY_FACTOR;
            reason  = "не указано (половина штрафа)";
        } else {
            penalty = full;
            reason  = "отсутствует";
        }
        items.add(ScoreBreakdown.TechnicalItem.builder()
                .requirement(label).penalty(round1(penalty)).reason(reason).build());
        return penalty;
    }

    private double addPowerItem(List<ScoreBreakdown.TechnicalItem> items, Integer required, Integer actual) {
        if (required == null || required.intValue() <= 0) return 0;
        double penalty;
        String reason;
        int req = required.intValue();
        if (actual == null) {
            penalty = 3.0 * UNKNOWN_FIELD_PENALTY_FACTOR;
            reason  = "мощность не указана (требовалось от " + req + " кВт)";
        } else {
            int act = actual.intValue();
            if (act >= req) return 0;
            double deficit = 1.0 - ((double) act / req);
            penalty = 3.0 * Math.min(1.0, Math.max(0.0, deficit));
            reason  = String.format("дефицит %.0f%% (%d из %d кВт)", deficit * 100, act, req);
        }
        items.add(ScoreBreakdown.TechnicalItem.builder()
                .requirement("мощность").penalty(round1(penalty)).reason(reason).build());
        return penalty;
    }

    private double addCeilingItem(List<ScoreBreakdown.TechnicalItem> items,
                                  BigDecimal required, BigDecimal actual) {
        if (required == null) return 0;
        double penalty;
        String reason;
        if (actual == null) {
            penalty = 2.0 * UNKNOWN_FIELD_PENALTY_FACTOR;
            reason  = "высота потолков не указана (требовалось от " + required + " м)";
        } else if (actual.compareTo(required) >= 0) {
            return 0;
        } else {
            double deficitMeters = required.subtract(actual).doubleValue();
            double factor = Math.min(1.0, deficitMeters / CEILING_FULL_PENALTY_DEFICIT_M);
            penalty = 2.0 * factor;
            reason  = String.format("потолки %s м ниже требуемых %s м (дефицит %.2f м)",
                    actual, required, deficitMeters);
        }
        items.add(ScoreBreakdown.TechnicalItem.builder()
                .requirement("потолки").penalty(round1(penalty)).reason(reason).build());
        return penalty;
    }

    private static double round1(double v) {
        return Math.round(v * 10.0) / 10.0;
    }

    // =========================================================================
    //  КОМПОНЕНТ 5: Транспортный мэтч (0–5 баллов)
    // =========================================================================

    private TransportResult calculateTransport(Property property, OverpassAreaSnapshot snapshot) {
        if (snapshot.isFailed()) {
            return new TransportResult(0, ScoreBreakdown.TransportPart.builder()
                    .nearestType("UNAVAILABLE")
                    .nearestDistanceMeters(-1)
                    .reason("Overpass недоступен — транспорт не оценён")
                    .build());
        }
        if (property.getLatitude() == null || property.getLongitude() == null) {
            return new TransportResult(0, ScoreBreakdown.TransportPart.builder()
                    .nearestType("NONE")
                    .nearestDistanceMeters(-1)
                    .reason("у помещения нет координат")
                    .build());
        }

        double lat = property.getLatitude().doubleValue();
        double lon = property.getLongitude().doubleValue();
        List<TransportStop> stops = snapshot.transportStops();

        if (stops.isEmpty()) {
            return new TransportResult(0, ScoreBreakdown.TransportPart.builder()
                    .nearestType("NONE")
                    .nearestDistanceMeters(-1)
                    .reason("в радиусе " + TRANSPORT_SEARCH_RADIUS_METERS + "м не найдено остановок")
                    .build());
        }

        TransportStop best = null;
        double bestEffective = Double.MAX_VALUE;
        double bestRealDistance = 0;
        for (TransportStop stop : stops) {
            if (stop.lat() == 0.0 && stop.lon() == 0.0) continue;
            double d = haversineMeters(lat, lon, stop.lat(), stop.lon());
            // Транспорт хотим в фиксированном радиусе TRANSPORT_SEARCH_RADIUS_METERS,
            // даже если общий Overpass-запрос захватил больше: ближайшая
            // станция в 3км не «бонус», а формальность.
            if (d > TRANSPORT_SEARCH_RADIUS_METERS) continue;
            double eff = d * stop.type().getDistancePenalty();
            if (eff < bestEffective) {
                bestEffective = eff;
                bestRealDistance = d;
                best = stop;
            }
        }
        if (best == null) {
            return new TransportResult(0, ScoreBreakdown.TransportPart.builder()
                    .nearestType("NONE")
                    .nearestDistanceMeters(-1)
                    .reason("остановки найдены, но без координат или вне радиуса")
                    .build());
        }

        double pointsD = MAX_TRANSPORT_SCORE * Math.exp(-bestEffective / TRANSPORT_SIGMA_METERS);
        int points = Math.max(0, Math.min(MAX_TRANSPORT_SCORE, (int) Math.round(pointsD)));

        String typeLabel = switch (best.type()) {
            case METRO -> "метро";
            case RAIL  -> "ж/д";
            case TRAM  -> "трамвай";
            case BUS   -> "автобус";
        };
        String reason = String.format("%s «%s» в %.0f м (бонус %d/%d)",
                typeLabel, best.name(), bestRealDistance, points, MAX_TRANSPORT_SCORE);

        log.info("[TRANSPORT] property={}: nearest={} type={} distance={}м effective={}м → {}/{}",
                property.getId(), best.name(), best.type(),
                (int) bestRealDistance, (int) bestEffective, points, MAX_TRANSPORT_SCORE);

        return new TransportResult(points, ScoreBreakdown.TransportPart.builder()
                .nearestName(best.name())
                .nearestType(best.type().name())
                .nearestDistanceMeters(Math.round(bestRealDistance))
                .reason(reason)
                .build());
    }

    // =========================================================================
    //  КОМПОНЕНТ 3 + 4: Анализ окрестности через Overpass API
    // =========================================================================

    private record NeighborhoodResult(
            int competitorScore,
            List<String> directNames,
            int synergyScore,
            List<String> synergyNames,
            ScoreBreakdown.CompetitorPart competitorPart,
            ScoreBreakdown.SynergyPart synergyPart
    ) {}

    private NeighborhoodResult analyzeNeighborhood(SearchProfile profile, Property property,
                                                    Map<String, List<BusinessCategory>> tagIndex,
                                                    OverpassAreaSnapshot snapshot) {
        // CASE A: Overpass упал — НЕ выставляем max-балл. Нули с понятным
        // reason'ом; общий dataStatus = OVERPASS_UNAVAILABLE, totalScore
        // считается только по fin+tech.
        if (snapshot.isFailed()) {
            ScoreBreakdown.CompetitorPart cp = ScoreBreakdown.CompetitorPart.builder()
                    .directRefs(List.of())
                    .totalNearbyBusinesses(0)
                    .radiusMeters(0)
                    .build();
            ScoreBreakdown.SynergyPart sp = ScoreBreakdown.SynergyPart.builder()
                    .desiredCategoriesCount(profile.getDesiredNeighbors() == null
                            ? 0 : profile.getDesiredNeighbors().size())
                    .foundCategoriesCount(0)
                    .refs(List.of())
                    .build();
            return new NeighborhoodResult(0, List.of(), 0, List.of(), cp, sp);
        }

        if (profile.getBusinessCategory() == null
                || property.getLatitude() == null
                || property.getLongitude() == null) {
            // Корректное «нет данных для оценки» — категория бизнеса не задана
            // или у помещения нет координат. Здесь max-балл оправдан: нечего
            // штрафовать. Это поведение отличается от FAILED.
            ScoreBreakdown.CompetitorPart cp = ScoreBreakdown.CompetitorPart.builder()
                    .directRefs(List.of())
                    .totalNearbyBusinesses(0).radiusMeters(0)
                    .build();
            ScoreBreakdown.SynergyPart sp = ScoreBreakdown.SynergyPart.builder()
                    .refs(List.of()).build();
            return new NeighborhoodResult(MAX_COMPETITOR_SCORE, List.of(),
                                          MAX_SYNERGY_SCORE, List.of(), cp, sp);
        }

        int competitorRadius = profile.getSearchRadiusMeters() != null
                ? Math.min(profile.getSearchRadiusMeters(), 5000)
                : 1000;
        int synergyRadius = profile.getSynergyRadiusMeters() != null
                ? Math.min(profile.getSynergyRadiusMeters(), 5000)
                : competitorRadius;
        // Сам Overpass-запрос был сделан на max(competitor, synergy, transport=1500),
        // здесь мы фильтруем результат по per-purpose радиусам.
        int radius = Math.max(competitorRadius, synergyRadius);

        BusinessCategory target = profile.getBusinessCategory();
        Long targetId = target.getId();
        Long targetParentId = target.getParentCategory() != null
                ? target.getParentCategory().getId()
                : null;
        boolean targetIsRoot = targetParentId == null;
        double lat = property.getLatitude().doubleValue();
        double lon = property.getLongitude().doubleValue();

        log.info("[COMP-CTX] property={} profile={} (id={}) targetCategory={} (id={}, parentId={}, isRoot={}) osmTags=[{}] competitorR={}м synergyR={}м",
                property.getId(), profile.getName(), profile.getId(),
                target.getName(), targetId, targetParentId, targetIsRoot, target.getOsmTags(),
                competitorRadius, synergyRadius);

        List<NearbyBusiness> nearbyBusinesses = snapshot.businesses();

        Set<Long> desiredNeighborIds = profile.getDesiredNeighbors() == null
                ? Set.of()
                : profile.getDesiredNeighbors().stream()
                         .map(BusinessCategory::getId)
                         .collect(Collectors.toSet());

        if (nearbyBusinesses.isEmpty()) {
            // Overpass ОК, но вокруг действительно ничего нет. Здесь max
            // оправдан: реальная ситуация «спальный район без конкурентов».
            int synergyEmpty = desiredNeighborIds.isEmpty() ? MAX_SYNERGY_SCORE : 0;
            log.warn("[COMP-EMPTY] property={}: Overpass успешно вернул ноль организаций " +
                            "(target='{}', desired={}). Балл по умолчанию {}/{}.",
                    property.getId(), target.getName(), desiredNeighborIds.size(),
                    MAX_COMPETITOR_SCORE, MAX_COMPETITOR_SCORE);
            ScoreBreakdown.CompetitorPart cp = ScoreBreakdown.CompetitorPart.builder()
                    .directRefs(List.of())
                    .totalNearbyBusinesses(0).radiusMeters(radius)
                    .build();
            ScoreBreakdown.SynergyPart sp = ScoreBreakdown.SynergyPart.builder()
                    .desiredCategoriesCount(desiredNeighborIds.size())
                    .foundCategoriesCount(0)
                    .refs(List.of()).build();
            return new NeighborhoodResult(MAX_COMPETITOR_SCORE, List.of(),
                                          synergyEmpty, List.of(), cp, sp);
        }

        final double sigma = Math.max(radius / DISTANCE_SIGMA_DIVISOR, 50.0);

        double weightedDirect = 0.0;
        long directCount = 0;
        List<ScoreBreakdown.CompetitorRef> directRanked = new ArrayList<>();
        List<Double> directRawWeights = new ArrayList<>();
        Map<Long, Double> synergyTotalPerCategory = new LinkedHashMap<>();
        List<ScoreBreakdown.SynergyRef> synergyAllRefs = new ArrayList<>();
        List<Set<Long>> synergyMatchesPerBusiness = new ArrayList<>();
        List<Double> synergyRawWeights = new ArrayList<>();

        for (NearbyBusiness business : nearbyBusinesses) {
            boolean isDirect = false;
            Set<Long> synergyMatchesForBusiness = new HashSet<>();

            Set<Long> matchedCatIds = new HashSet<>();
            for (String rubric : business.rubrics()) {
                List<BusinessCategory> cats = tagIndex.get(rubric);
                if (cats == null) continue;
                for (BusinessCategory c : cats) matchedCatIds.add(c.getId());
            }

            for (Long catId : matchedCatIds) {
                BusinessCategory matched = findById(catId, tagIndex);
                Long matchedParentId = (matched != null && matched.getParentCategory() != null)
                        ? matched.getParentCategory().getId() : null;

                if (!isDirect) {
                    if (targetIsRoot) {
                        if (targetId.equals(matchedParentId) || targetId.equals(catId)) {
                            isDirect = true;
                        }
                    } else {
                        if (catId.equals(targetId)) {
                            isDirect = true;
                        }
                    }
                }
                if (desiredNeighborIds.contains(catId)) {
                    synergyMatchesForBusiness.add(catId);
                } else if (matchedParentId != null && desiredNeighborIds.contains(matchedParentId)) {
                    synergyMatchesForBusiness.add(matchedParentId);
                }
            }

            double distanceMeters = (business.lat() == 0.0 && business.lon() == 0.0)
                    ? -1.0
                    : haversineMeters(lat, lon, business.lat(), business.lon());
            double weight = distanceWeight(lat, lon, business, sigma);

            boolean hasCoords = !(business.lat() == 0.0 && business.lon() == 0.0);
            Double bLat = hasCoords ? business.lat() : null;
            Double bLon = hasCoords ? business.lon() : null;

            boolean withinCompetitorRadius = distanceMeters < 0 || distanceMeters <= competitorRadius;
            boolean withinSynergyRadius    = distanceMeters < 0 || distanceMeters <= synergyRadius;

            if (withinCompetitorRadius && isDirect) {
                directCount++;
                weightedDirect += weight;
                directRanked.add(buildCompetitorRef(business.name(), distanceMeters, weight, bLat, bLon));
                directRawWeights.add(weight);
            }

            if (withinSynergyRadius && !synergyMatchesForBusiness.isEmpty()) {
                ScoreBreakdown.SynergyRef ref = ScoreBreakdown.SynergyRef.builder()
                        .name(business.name())
                        .distanceMeters(distanceMeters < 0 ? -1 : Math.round(distanceMeters))
                        .weight(round2(weight))
                        .latitude(bLat)
                        .longitude(bLon)
                        .build();
                synergyAllRefs.add(ref);
                synergyMatchesPerBusiness.add(synergyMatchesForBusiness);
                synergyRawWeights.add(weight);
                for (Long catId : synergyMatchesForBusiness) {
                    synergyTotalPerCategory.merge(catId, weight, Double::sum);
                }
            }
        }

        log.info("[COMP-SCORE] property={}: прямых={} (вес={}), всего бизнесов в радиусе={}, σ={}м",
                property.getId(),
                directCount, String.format("%.2f", weightedDirect),
                nearbyBusinesses.size(), (int) sigma);

        if (directCount == 0 && !nearbyBusinesses.isEmpty()) {
            int sample = Math.min(5, nearbyBusinesses.size());
            log.warn("[COMP-NO-MATCH] property={}: ни один из {} бизнесов не классифицирован как прямой конкурент. Первые {} для проверки тегов:",
                    property.getId(), nearbyBusinesses.size(), sample);
            for (int i = 0; i < sample; i++) {
                NearbyBusiness b = nearbyBusinesses.get(i);
                log.warn("[COMP-NO-MATCH]   {} → теги: {}", b.name(), b.rubrics());
            }
        }

        double competitorScoreD = MAX_COMPETITOR_SCORE
                * Math.exp(-COMPETITOR_DECAY_K_DIRECT * weightedDirect);
        int competitorScore = (int) Math.round(competitorScoreD);
        competitorScore = Math.max(0, Math.min(MAX_COMPETITOR_SCORE, competitorScore));

        double totalLost = MAX_COMPETITOR_SCORE - competitorScoreD;
        if (weightedDirect > 0.0) {
            for (int i = 0; i < directRanked.size(); i++) {
                double wRaw = directRawWeights.get(i);
                double impact = -totalLost * (wRaw / weightedDirect);
                directRanked.get(i).setScoreImpact(round2(impact));
            }
        }

        directRanked.sort(Comparator.comparingDouble(ScoreBreakdown.CompetitorRef::getWeight).reversed());
        List<String> directNames = directRanked.stream().map(ScoreBreakdown.CompetitorRef::getName).collect(Collectors.toList());

        int synergyScore;
        List<String> synergyNames = new ArrayList<>();
        List<ScoreBreakdown.SynergyRef> synergyRefs = new ArrayList<>();
        if (desiredNeighborIds.isEmpty()) {
            synergyScore = MAX_SYNERGY_SCORE;
        } else {
            double sumPerCategory = 0.0;
            for (Long catId : desiredNeighborIds) {
                Double totalW = synergyTotalPerCategory.get(catId);
                double pc = totalW == null ? 0.0 : 1.0 - Math.exp(-totalW / SYNERGY_SATURATION_K);
                sumPerCategory += pc;
            }
            double normalized = sumPerCategory / desiredNeighborIds.size();
            double synergyScoreD = MAX_SYNERGY_SCORE * normalized;
            synergyScore = (int) Math.round(synergyScoreD);
            synergyScore = Math.max(0, Math.min(MAX_SYNERGY_SCORE, synergyScore));

            double unit = (double) MAX_SYNERGY_SCORE / desiredNeighborIds.size();
            for (int i = 0; i < synergyAllRefs.size(); i++) {
                ScoreBreakdown.SynergyRef ref = synergyAllRefs.get(i);
                Set<Long> matches = synergyMatchesPerBusiness.get(i);
                double wRaw = synergyRawWeights.get(i);
                double impact = 0.0;
                for (Long catId : matches) {
                    Double totalW = synergyTotalPerCategory.get(catId);
                    if (totalW == null || totalW <= 0.0) continue;
                    double pc = 1.0 - Math.exp(-totalW / SYNERGY_SATURATION_K);
                    impact += unit * pc * (wRaw / totalW);
                }
                ref.setScoreImpact(round2(impact));
            }

            synergyAllRefs.stream()
                    .sorted(Comparator.comparingDouble(ScoreBreakdown.SynergyRef::getWeight).reversed())
                    .forEach(ref -> { synergyNames.add(ref.getName()); synergyRefs.add(ref); });
        }

        log.info("[SYNERGY] property={}: желаемых соседей={}, найдено категорий={}, найдено бизнесов={}, балл={}/{}",
                property.getId(), desiredNeighborIds.size(),
                synergyTotalPerCategory.size(), synergyAllRefs.size(), synergyScore, MAX_SYNERGY_SCORE);

        ScoreBreakdown.CompetitorPart competitorPart = ScoreBreakdown.CompetitorPart.builder()
                .weightedDirect(round2(weightedDirect))
                .directRefs(directRanked)
                .totalNearbyBusinesses(nearbyBusinesses.size())
                .radiusMeters(radius)
                .build();
        ScoreBreakdown.SynergyPart synergyPart = ScoreBreakdown.SynergyPart.builder()
                .desiredCategoriesCount(desiredNeighborIds.size())
                .foundCategoriesCount(synergyTotalPerCategory.size())
                .refs(synergyRefs)
                .build();

        return new NeighborhoodResult(competitorScore, directNames,
                                      synergyScore, synergyNames,
                                      competitorPart, synergyPart);
    }

    private ScoreBreakdown.CompetitorRef buildCompetitorRef(String name, double distanceMeters, double weight,
                                                            Double latitude, Double longitude) {
        return ScoreBreakdown.CompetitorRef.builder()
                .name(name)
                .distanceMeters(distanceMeters < 0 ? -1 : Math.round(distanceMeters))
                .weight(round2(weight))
                .latitude(latitude)
                .longitude(longitude)
                .build();
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    private double distanceWeight(double propertyLat, double propertyLon,
                                  NearbyBusiness business, double sigma) {
        double bLat = business.lat();
        double bLon = business.lon();
        if (bLat == 0.0 && bLon == 0.0) {
            return FALLBACK_WEIGHT_MISSING_COORDS;
        }
        double dist = haversineMeters(propertyLat, propertyLon, bLat, bLon);
        return Math.exp(-dist / sigma);
    }

    private double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                 * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_METERS * c;
    }

    // =========================================================================
    //  HELPERS: индекс OSM-тег → категории
    // =========================================================================

    private Map<String, List<BusinessCategory>> buildTagIndex(List<BusinessCategory> categories) {
        Map<String, List<BusinessCategory>> index = new HashMap<>();
        for (BusinessCategory cat : categories) {
            String csv = cat.getOsmTags();
            if (csv == null || csv.isBlank()) continue;
            for (String raw : csv.split(",")) {
                String tag = raw.trim().toLowerCase();
                if (tag.isEmpty() || !tag.contains("=")) continue;
                index.computeIfAbsent(tag, k -> new ArrayList<>()).add(cat);
            }
        }
        return index;
    }

    private BusinessCategory findById(Long id, Map<String, List<BusinessCategory>> tagIndex) {
        for (List<BusinessCategory> bucket : tagIndex.values()) {
            for (BusinessCategory c : bucket) {
                if (id.equals(c.getId())) return c;
            }
        }
        return null;
    }

    // =========================================================================
    //  ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
    // =========================================================================

    private String resolveMatchLabel(int score) {
        if (score >= 75) return "🔥 Отличный мэтч!";
        if (score >= 50) return "👍 Хороший вариант";
        if (score >= 25) return "⚠️ Частичное совпадение";
        return "❌ Не подходит";
    }

    private String resolveMatchColor(int score) {
        if (score >= 75) return "green";
        if (score >= 50) return "yellow";
        return "red";
    }
}
