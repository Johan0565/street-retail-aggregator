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
 * Источник данных о соседях — OpenStreetMap через Overpass API.
 * Один запрос на помещение возвращает ВСЕ организации в радиусе с их
 * OSM-тегами. Категория сматчена с организацией, если хотя бы один её
 * "key=value"-тег ({@link BusinessCategory#getOsmTags()}) совпадает с
 * тегами организации. Этим решена ключевая проблема предыдущих
 * Yandex/2GIS-вариантов: прямой конкурент той же категории (аптека рядом
 * с целевой аптекой) больше не теряется в выдаче — Overpass отдаёт все
 * POI без лимитов на «релевантность».
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class PropertyScoringService {

    private final OverpassPlacesService overpassPlacesService;
    private final BusinessCategoryRepository businessCategoryRepository;

    private static final int MAX_FINANCIAL_SCORE   = 20;
    private static final int MAX_TECHNICAL_SCORE   = 20;
    private static final int MAX_COMPETITOR_SCORE  = 40;
    private static final int MAX_SYNERGY_SCORE     = 15;
    private static final int MAX_TRANSPORT_SCORE   = 5;

    // --- Транспорт: характерная пешеходная дистанция ---
    // σ_transport = 500м. Метро в 0м → 5; в 250м → 3.0; в 500м → 1.8; в 1км → 0.7.
    // Для автобуса дистанция умножается на 2.0 (см. TransportType.distancePenalty).
    private static final double TRANSPORT_SIGMA_METERS = 500.0;
    // Радиус поиска транспорта фиксирован: бизнес-радиус арендатора может быть
    // мал (например 300м), а ближайшая станция — в 800м. Для UX важнее знать
    // «есть ли метро поблизости вообще», чем рассчитывать строго по фильтру.
    private static final int TRANSPORT_SEARCH_RADIUS_METERS = 1500;

    // --- Финансовый блок: half / half между бюджетом и площадью ---
    private static final double BUDGET_AXIS_MAX = 10.0;
    private static final double AREA_AXIS_MAX   = 10.0;
    // Жёсткость спада, когда цена превышает бюджет. +20% → ~5.5, +50% → ~2.2.
    private static final double BUDGET_OVER_DECAY = 3.0;
    // Площадь ниже минимума — жёсткий decay (бизнес может не влезть).
    private static final double AREA_UNDER_DECAY  = 4.0;
    // Площадь выше максимума — мягкий decay (платят за лишние м², но рабочее).
    private static final double AREA_OVER_DECAY   = 1.5;

    // --- Технический блок: половинный штраф при «неизвестно» ---
    private static final double UNKNOWN_FIELD_PENALTY_FACTOR = 0.5;
    // Полностью «провалить» по потолкам должно при дефиците ≥ этой величины (м).
    private static final double CEILING_FULL_PENALTY_DEFICIT_M = 0.3;

    // --- Параметры алгоритма distance-aware скоринга соседей ---
    // Характерная дистанция decay'a берётся как radius / SIGMA_DIVISOR. При
    // радиусе 1000м σ≈333м, и конкурент за 1км даёт вес exp(-3)≈0.05. То есть
    // далёкие POI почти не влияют, ближние влияют сильно — устраняем главный
    // дефект прежней step-функции «5+ direct = 0» в плотных районах вроде Мск.
    private static final double DISTANCE_SIGMA_DIVISOR = 3.0;
    // Жёсткость экспоненциального спада итогового балла конкурентов.
    // Калибровка: один близкий direct (вес≈0.86) → score≈12.8 (≈ прежние 12).
    private static final double COMPETITOR_DECAY_K_DIRECT   = 1.0;
    // Если Overpass не отдал координаты конкретного POI — используем «средний»
    // вес, чтобы он всё-таки участвовал в формуле, но не доминировал.
    private static final double FALLBACK_WEIGHT_MISSING_COORDS = 0.2;
    private static final double EARTH_RADIUS_METERS = 6_371_000.0;

    // --- Синергия: насыщающаяся сумма весов на категорию ---
    // per_category = 1 - exp(-Σweight_i / K). Прежний вариант «брать только
    // ближайшего» приводил к 6/15 при 200+ соседях в 2 категориях, потому что
    // одиночный сосед в ~300м даёт weight≈0.4, и 0.4*15=6. Теперь любое скопление
    // соседей в категории насыщает её вклад до 1.0.
    // Калибровка K=0.7: один сосед «у двери» (weight=1) → 0.76, два по weight=0.5
    // (Σ=1) → 0.76, пять в 300м (Σ≈2) → 0.94. Большая «масса» соседей быстро
    // выходит на плато, как и должно быть для понятия «синергия».
    private static final double SYNERGY_SATURATION_K = 0.7;

    // =========================================================================
    //  ПУБЛИЧНЫЕ МЕТОДЫ
    // =========================================================================

    public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
        List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
        Map<String, List<BusinessCategory>> tagIndex = buildTagIndex(allCategories);
        return properties.stream()
                .map(p -> scoreInternal(profile, p, tagIndex))
                .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
                .collect(Collectors.toList());
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
        NeighborhoodResult neighborhood = analyzeNeighborhood(profile, property, tagIndex);
        TransportResult transport = calculateTransport(property);

        int total = financial.score() + technical.score()
                  + neighborhood.competitorScore() + neighborhood.synergyScore()
                  + transport.score();

        log.debug("Scoring [{}]: total={}, fin={}, tech={}, comp={}, syn={}, trans={}",
                property.getId(), total, financial.score(), technical.score(),
                neighborhood.competitorScore(), neighborhood.synergyScore(), transport.score());

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
                .matchLabel(resolveMatchLabel(total))
                .matchColor(resolveMatchColor(total))
                .breakdown(breakdown)
                .build();
    }

    private record FinancialResult(int score, ScoreBreakdown.FinancialPart part) {}
    private record TechnicalResult(int score, ScoreBreakdown.TechnicalPart part) {}
    private record TransportResult(int score, ScoreBreakdown.TransportPart part) {}

    // =========================================================================
    //  КОМПОНЕНТ 1: Финансовый мэтч (0–20 баллов)
    //
    //  Две независимые оси по 10 баллов: бюджет и площадь.
    //
    //  Бюджет (0–10):
    //    цена ≤ maxBudget  → 10 (включая «дешевле минимума» — это плюс)
    //    цена > maxBudget  → 10 · exp(-3 · over_ratio),  over_ratio = (p-max)/max
    //                        +10% → 7.4, +20% → 5.5, +50% → 2.2, +100% → 0.5
    //
    //  Площадь (0–10):
    //    area ∈ [min, max]    → 10
    //    area < minArea       → 10 · exp(-4 · deficit),   жёстче (не влезет)
    //                           -5% → 8.2, -20% → 4.5, -50% → 1.4
    //    area > maxArea       → 10 · exp(-1.5 · over),    мягче (платят за лишнее)
    //                           +10% → 8.6, +50% → 4.7, +100% → 2.2
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
    //
    //  Принципы:
    //   - Булевы требования (вода, вентиляция, WC и т.д.) штрафуются на полный
    //     вес при FALSE и на половину при null — «не указано» ≠ «отсутствует».
    //   - Мощность и потолки — градиентные штрафы, пропорциональные дефициту:
    //       power_deficit  = 1 - actual/required    (clamped в [0,1])
    //       ceiling_deficit_factor = min(1, (req - actual) / 0.3 м)
    //     Близкое к норме значение почти не штрафуется, сильное отклонение —
    //     до полного веса.
    //   - SHELL_AND_CORE больше не даёт безусловного штрафа: состояние ремонта
    //     не пересекается с требованиями профиля, и универсальный минус был
    //     просто шумом в скоринге.
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
    //
    //  effective_distance = closest_stop.distance * type.distancePenalty
    //  score = 5 * exp(-effective_distance / σ_transport)
    //
    //  σ_transport = 500м. Метро/жд: penalty = 1.0; трамвай: 1.4; автобус: 2.0.
    //  Пример: метро в 250м → ~3.0/5; автобус в 250м → effective 500м → ~1.8/5.
    // =========================================================================

    private TransportResult calculateTransport(Property property) {
        if (property.getLatitude() == null || property.getLongitude() == null) {
            return new TransportResult(0, ScoreBreakdown.TransportPart.builder()
                    .nearestType("NONE")
                    .nearestDistanceMeters(-1)
                    .reason("у помещения нет координат")
                    .build());
        }

        double lat = property.getLatitude().doubleValue();
        double lon = property.getLongitude().doubleValue();
        List<TransportStop> stops = overpassPlacesService.searchTransportNearby(
                lat, lon, TRANSPORT_SEARCH_RADIUS_METERS);

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
                    .reason("остановки найдены, но без координат")
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
    //
    //  Конкуренты (0–40 баллов) — distance-aware smooth decay:
    //    weight_i = exp(-distance_i / σ),  σ = radius / 3
    //    weightedDirect   = Σ weight_i по прямым конкурентам
    //    competitorScore  = 40 * exp(-1.0 * weightedDirect)
    //
    //  Почему так, а не step-функция: в Москве в радиусе 1км может быть 50+
    //  организаций той же категории, и прежняя «5+ direct = 0» обнуляла все
    //  адреса в плотных районах. Теперь 5 далёких конкурентов (по 900м) дают
    //  ~23/40, 5 близких (по 50м) — ~1/40, а абсолютные числа не клипают
    //  значение в 0. Понятие «косвенный конкурент» убрано: на практике
    //  оно даёт шум — соседняя пекарня для кофейни всё равно «магнит»,
    //  а не угроза, и пользователи путались с тем, почему такие POI
    //  «снимают» баллы.
    //
    //  Синергия (0–15 баллов) — distance-aware, насыщающаяся сумма весов:
    //    Для каждой желаемой категории суммируем веса всех найденных POI и
    //    прогоняем через 1-exp(-Σ/K). Один сосед даёт значимый вклад,
    //    скопление быстро выходит на плато 1.0. Усредняем по всем желаемым
    //    категориям, домножаем на 15. Сосед через дорогу весит больше, чем
    //    через 1км; «100 кафе» уже не сводятся к «один ближайший».
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
                                                    Map<String, List<BusinessCategory>> tagIndex) {
        if (profile.getBusinessCategory() == null
                || property.getLatitude() == null
                || property.getLongitude() == null) {
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
        // Радиус для соседей-синергии может отличаться: например, конкурентов
        // ищем в 300м, а кафе-«магниты» — в 1.5км. Если у проекта нет своего
        // значения (старые профили / не задано), падаем обратно на общий.
        int synergyRadius = profile.getSynergyRadiusMeters() != null
                ? Math.min(profile.getSynergyRadiusMeters(), 5000)
                : competitorRadius;
        // Overpass запрашиваем по большему радиусу, чтобы оба фильтра имели
        // данные. Потом per-purpose отсекаем по расстоянию.
        int radius = Math.max(competitorRadius, synergyRadius);

        BusinessCategory target = profile.getBusinessCategory();
        Long targetId = target.getId();
        Long targetParentId = target.getParentCategory() != null
                ? target.getParentCategory().getId()
                : null;
        // Корневая категория (например «Еда и напитки») сама не имеет osmTags,
        // её роль — контейнер. Если арендатор выбрал корень, прямыми считаются
        // ВСЕ подкатегории-дети этого корня (кафе+ресторан+пекарня и т.д.).
        boolean targetIsRoot = targetParentId == null;
        double lat = property.getLatitude().doubleValue();
        double lon = property.getLongitude().doubleValue();

        log.info("[COMP-CTX] property={} profile={} (id={}) targetCategory={} (id={}, parentId={}, isRoot={}) osmTags=[{}] competitorR={}м synergyR={}м (overpassR={}м)",
                property.getId(), profile.getName(), profile.getId(),
                target.getName(), targetId, targetParentId, targetIsRoot, target.getOsmTags(),
                competitorRadius, synergyRadius, radius);

        // ------- Одно обращение к Overpass за всеми соседями -------
        List<NearbyBusiness> nearbyBusinesses = overpassPlacesService.searchNearby(lat, lon, radius);

        Set<Long> desiredNeighborIds = profile.getDesiredNeighbors() == null
                ? Set.of()
                : profile.getDesiredNeighbors().stream()
                         .map(BusinessCategory::getId)
                         .collect(Collectors.toSet());

        if (nearbyBusinesses.isEmpty()) {
            int synergyEmpty = desiredNeighborIds.isEmpty() ? MAX_SYNERGY_SCORE : 0;
            log.warn("[COMP-EMPTY] property={}: Overpass не вернул ни одной организации " +
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

        // ------- Классификация: direct / synergy с distance-aware весами -------
        final double sigma = Math.max(radius / DISTANCE_SIGMA_DIVISOR, 50.0);

        double weightedDirect = 0.0;
        long directCount = 0;
        // {name, distance, weight} для UI/AI: сортируем по близости.
        List<ScoreBreakdown.CompetitorRef> directRanked = new ArrayList<>();
        // Сырые веса конкурентов (без округления до 2 знаков) — для атрибуции
        // impact пропорционально полному w, иначе дальние POI с весом <0.005
        // округляются в 0 и их доля от потери баллов исчезает.
        List<Double> directRawWeights = new ArrayList<>();
        // Для синергии:
        //  - synergyTotalPerCategory — сумма весов всех соседей по каждой
        //    желаемой категории. Используется в насыщающейся формуле
        //    1 - exp(-Σ/K), чтобы скопление соседей давало больший балл,
        //    чем один ближайший.
        //  - synergyMatchesPerBusiness — список категорий, под которые
        //    подпал каждый бизнес. Нужен потом для расчёта scoreImpact:
        //    маржинальный вклад «без этого POI» по каждой его категории.
        //  - synergyAllRefs — ВСЕ найденные совпадения, для списка в UI.
        Map<Long, Double> synergyTotalPerCategory = new LinkedHashMap<>();
        List<ScoreBreakdown.SynergyRef> synergyAllRefs = new ArrayList<>();
        List<Set<Long>> synergyMatchesPerBusiness = new ArrayList<>();
        // Сырые (не округлённые до 2 знаков) веса POI для атрибуции импактов.
        // Без них дальние POI с весом <0.005 после round2 становятся 0 и не
        // получают своей доли от per_category, хотя в Σw_категории они учтены.
        // Тогда сумма видимых +X.X не сходится с балом синергии.
        List<Double> synergyRawWeights = new ArrayList<>();

        for (NearbyBusiness business : nearbyBusinesses) {
            boolean isDirect = false;
            Set<Long> synergyMatchesForBusiness = new HashSet<>();

            // Собираем все категории, под которые подпадает бизнес,
            // через индекс OSM-тегов. Один и тот же бизнес может попасть
            // под несколько категорий — это нормально (например shop=beauty
            // → и «Салон красоты», и «Косметология»).
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
                        // цель — корень: прямым считаем любую категорию,
                        // у которой parent == target (т.е. подкатегория цели)
                        if (targetId.equals(matchedParentId) || targetId.equals(catId)) {
                            isDirect = true;
                        }
                    } else {
                        // цель — лист: прямой == точное совпадение id
                        if (catId.equals(targetId)) {
                            isDirect = true;
                        }
                    }
                }
                // Синергия: матчим как по точному id, так и по родителю —
                // иначе выбор «корневой» категории желаемого соседа (например,
                // «Кафе и рестораны») не подхватывал бы бизнесы в её подкатегориях
                // («Кофейня», «Ресторан»), хотя для конкурентов та же проверка
                // через matchedParentId уже работает.
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

            // Отсекаем по purpose-specific радиусу. Бизнесы без координат
            // (distanceMeters < 0) пропускаем в оба фильтра — у них только
            // FALLBACK_WEIGHT и они не могут быть исключены геометрически.
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

        // Сколько каждый конкурент «съел» из competitorScore.
        // Общая потеря = MAX - score; делим её между конкурентами
        // пропорционально их СЫРОМУ весу (w_i / Σw). Это единственная разбивка,
        // при которой Σ impacts по списку = (MAX - score). Используем сырой
        // вес, а не ref.getWeight() (тот округлён до 2 знаков и обнуляет
        // дальние POI), чтобы сумма импактов сходилась с реальной потерей.
        // Атрибуцию делаем до сортировки, пока indices синхронны с
        // directRawWeights.
        double totalLost = MAX_COMPETITOR_SCORE - competitorScoreD;
        if (weightedDirect > 0.0) {
            for (int i = 0; i < directRanked.size(); i++) {
                double wRaw = directRawWeights.get(i);
                double impact = -totalLost * (wRaw / weightedDirect);
                directRanked.get(i).setScoreImpact(round2(impact));
            }
        }

        // Сортировка по близости: ближайший конкурент первым (после атрибуции,
        // чтобы не сломать соответствие с directRawWeights).
        directRanked.sort(Comparator.comparingDouble(ScoreBreakdown.CompetitorRef::getWeight).reversed());
        List<String> directNames = directRanked.stream().map(ScoreBreakdown.CompetitorRef::getName).collect(Collectors.toList());

        int synergyScore;
        List<String> synergyNames = new ArrayList<>();
        List<ScoreBreakdown.SynergyRef> synergyRefs = new ArrayList<>();
        if (desiredNeighborIds.isEmpty()) {
            synergyScore = MAX_SYNERGY_SCORE;
        } else {
            // Скоринг — насыщающаяся сумма весов на категорию:
            //   per_category = 1 - exp(-Σ / K)
            //   normalized   = avg(per_category по всем желаемым категориям)
            // Так скопление 100 соседей в категории доводит её вклад до 1.0,
            // а единичный далёкий сосед даёт мало — это и есть ожидание
            // «много магнитов = синергия большая».
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

            // Атрибуция баллов на POI: для каждой категории её вклад
            // unit · per_category делим между всеми соседями этой категории
            // ПРОПОРЦИОНАЛЬНО их весу (доля w_i / Σw_категории). Это
            // единственная разбивка, при которой Σ impacts по списку
            // строго равна synergyScore. Если соседа считать через
            // маржинал «что без него было бы», насыщающая функция
            // приписывает каждому почти ноль, и сумма уходит ниже балла —
            // именно так получалось «12/15 в шапке vs 4 в сумме списка».
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

            // UI-список — ВСЕ найденные соседи (как у конкурентов), сортируем
            // по близости.
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

    /**
     * Возвращает вес соседа: {@code exp(-distance / σ)} в [0,1]. Если у POI
     * нет координат (Overpass иногда не отдаёт center для way/relation),
     * используем мягкий fallback, чтобы такой POI всё же учитывался.
     */
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

    /**
     * Строит {@code Map<"key=value", List<BusinessCategory>>}, чтобы для
     * каждой OSM-рубрики бизнеса находить совпадающие категории за O(1).
     * Одна и та же пара ("shop=beauty") может вести к нескольким
     * категориям (Салон красоты + Косметология) — это намеренно: оба
     * считаются конкурентами при выборе любой из них.
     */
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
