package com.example.backend.service;

import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.BusinessCategory;
import com.example.backend.entity.Property;
import com.example.backend.entity.SearchProfile;
import com.example.backend.entity.enums.RepairState;
import com.example.backend.repository.BusinessCategoryRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Скоринг помещений по четырём компонентам (итого 0–100 баллов):
 *
 *   Финансовый мэтч   0–30  — площадь и бюджет
 *   Технический мэтч  0–20  — 8 критериев + ремонт
 *   Конкуренты        0–30  — все организации в радиусе через Overpass API
 *   Синергия          0–20  — соседство с желаемыми категориями
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

    private static final int MAX_FINANCIAL_SCORE   = 30;
    private static final int MAX_TECHNICAL_SCORE   = 20;
    private static final int MAX_COMPETITOR_SCORE  = 30;
    private static final int MAX_SYNERGY_SCORE     = 20;

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
        int financial = calculateFinancialScore(profile, property);
        int technical = calculateTechnicalScore(profile, property);
        NeighborhoodResult neighborhood = analyzeNeighborhood(profile, property, tagIndex);
        int total = financial + technical + neighborhood.competitorScore() + neighborhood.synergyScore();

        log.debug("Scoring [{}]: total={}, fin={}, tech={}, comp={}, syn={}",
                property.getId(), total, financial, technical,
                neighborhood.competitorScore(), neighborhood.synergyScore());

        return ScoredPropertyDto.builder()
                .property(property)
                .totalScore(total)
                .financialScore(financial)
                .technicalScore(technical)
                .competitorScore(neighborhood.competitorScore())
                .synergyScore(neighborhood.synergyScore())
                .directCompetitorNames(neighborhood.directNames())
                .indirectCompetitorNames(neighborhood.indirectNames())
                .synergyNeighborNames(neighborhood.synergyNames())
                .matchLabel(resolveMatchLabel(total))
                .matchColor(resolveMatchColor(total))
                .build();
    }

    // =========================================================================
    //  КОМПОНЕНТ 1: Финансовый мэтч (0–30 баллов)
    // =========================================================================

    private int calculateFinancialScore(SearchProfile profile, Property property) {
        int score = 0;

        if (property.getAreaSqm() != null) {
            if (isInRange(property.getAreaSqm(), profile.getMinArea(), profile.getMaxArea())) {
                score += 15;
            } else {
                score += partialScore(property.getAreaSqm(), profile.getMinArea(), profile.getMaxArea(), 15);
            }
        }

        if (property.getPricePerMonth() != null) {
            if (isInRange(property.getPricePerMonth(), profile.getMinBudget(), profile.getMaxBudget())) {
                score += 15;
            } else {
                score += partialScore(property.getPricePerMonth(), profile.getMinBudget(), profile.getMaxBudget(), 15);
            }
        }

        return Math.min(score, MAX_FINANCIAL_SCORE);
    }

    // =========================================================================
    //  КОМПОНЕНТ 2: Технический мэтч (0–20 баллов)
    // =========================================================================

    private int calculateTechnicalScore(SearchProfile profile, Property property) {
        int score = MAX_TECHNICAL_SCORE;

        if (Boolean.TRUE.equals(profile.getRequiresWater()) && !Boolean.TRUE.equals(property.getHasWater()))
            score -= 4;
        if (Boolean.TRUE.equals(profile.getRequiresVentilation()) && !Boolean.TRUE.equals(property.getHasVentilation()))
            score -= 4;
        if (Boolean.TRUE.equals(profile.getRequiresSeparateEntrance()) && !Boolean.TRUE.equals(property.getHasSeparateEntrance()))
            score -= 3;
        if (profile.getMinPowerKw() != null && profile.getMinPowerKw() > 0) {
            int power = property.getPowerKw() != null ? property.getPowerKw() : 0;
            if (power < profile.getMinPowerKw()) score -= 3;
        }
        if (Boolean.TRUE.equals(profile.getRequiresWc()) && !Boolean.TRUE.equals(property.getHasWc()))
            score -= 3;
        if (Boolean.TRUE.equals(profile.getRequiresParking()) && !Boolean.TRUE.equals(property.getHasParking()))
            score -= 2;
        if (Boolean.TRUE.equals(profile.getRequiresLoadingZone()) && !Boolean.TRUE.equals(property.getHasLoadingZone()))
            score -= 2;
        if (profile.getMinCeilingHeight() != null && property.getCeilingHeight() != null
                && property.getCeilingHeight().compareTo(profile.getMinCeilingHeight()) < 0)
            score -= 2;

        if (property.getRepairState() == RepairState.SHELL_AND_CORE) score -= 1;

        return Math.max(score, 0);
    }

    // =========================================================================
    //  КОМПОНЕНТ 3 + 4: Анализ окрестности через Overpass API
    //
    //  Конкуренты (0–30 баллов):
    //    Прямые  | Косвенные | Балл
    //    --------|-----------|-----
    //    0       | 0         | 30
    //    0       | 1–2       | 24
    //    0       | 3–5       | 18
    //    0       | 6+        | 12
    //    1       | —         | 12
    //    2       | —         |  6
    //    3–4     | —         |  3
    //    5+      | —         |  0
    //
    //  Синергия (0–20 баллов) — round(20 * найденных_категорий / желаемых_категорий)
    // =========================================================================

    private record NeighborhoodResult(
            int competitorScore,
            List<String> directNames,
            List<String> indirectNames,
            int synergyScore,
            List<String> synergyNames
    ) {}

    private NeighborhoodResult analyzeNeighborhood(SearchProfile profile, Property property,
                                                    Map<String, List<BusinessCategory>> tagIndex) {
        if (profile.getBusinessCategory() == null
                || property.getLatitude() == null
                || property.getLongitude() == null) {
            return new NeighborhoodResult(MAX_COMPETITOR_SCORE, List.of(), List.of(),
                                          MAX_SYNERGY_SCORE, List.of());
        }

        int radius = profile.getSearchRadiusMeters() != null
                ? Math.min(profile.getSearchRadiusMeters(), 5000)
                : 1000;

        BusinessCategory target = profile.getBusinessCategory();
        Long targetId = target.getId();
        Long targetParentId = target.getParentCategory() != null
                ? target.getParentCategory().getId()
                : null;
        // Корневая категория (например «Еда и напитки») сама не имеет osmTags,
        // её роль — контейнер. Если арендатор выбрал корень, прямыми считаются
        // ВСЕ подкатегории-дети этого корня (кафе+ресторан+пекарня и т.д.),
        // а «косвенных» для такой цели не бывает.
        boolean targetIsRoot = targetParentId == null;
        double lat = property.getLatitude().doubleValue();
        double lon = property.getLongitude().doubleValue();

        log.info("[COMP-CTX] property={} profile={} (id={}) targetCategory={} (id={}, parentId={}, isRoot={}) osmTags=[{}] radius={}м",
                property.getId(), profile.getName(), profile.getId(),
                target.getName(), targetId, targetParentId, targetIsRoot, target.getOsmTags(), radius);

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
                            "(target='{}', desired={}). Балл по умолчанию 30/30.",
                    property.getId(), target.getName(), desiredNeighborIds.size());
            return new NeighborhoodResult(MAX_COMPETITOR_SCORE, List.of(), List.of(),
                                          synergyEmpty, List.of());
        }

        // ------- Классификация: direct / indirect / synergy -------
        long direct   = 0;
        long indirect = 0;
        List<String> directNames   = new ArrayList<>();
        List<String> indirectNames = new ArrayList<>();
        Map<Long, List<String>> synergyByCategory = new LinkedHashMap<>();

        for (NearbyBusiness business : nearbyBusinesses) {
            boolean isDirect   = false;
            boolean isIndirect = false;
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
                if (!isIndirect && !isDirect && !targetIsRoot && targetParentId != null) {
                    // косвенный — sibling (общий родитель), только для листовых целей
                    if (targetParentId.equals(matchedParentId)) {
                        isIndirect = true;
                    }
                }
                if (desiredNeighborIds.contains(catId)) {
                    synergyMatchesForBusiness.add(catId);
                }
            }

            if (isDirect)        { direct++;   directNames.add(business.name()); }
            else if (isIndirect) { indirect++; indirectNames.add(business.name()); }

            for (Long catId : synergyMatchesForBusiness) {
                synergyByCategory.computeIfAbsent(catId, k -> new ArrayList<>()).add(business.name());
            }
        }

        log.info("[COMP-SCORE] property={}: прямых={} {}, косвенных={} {}, всего бизнесов в радиусе={}",
                property.getId(), direct, directNames, indirect, indirectNames, nearbyBusinesses.size());

        if (direct == 0 && indirect == 0 && !nearbyBusinesses.isEmpty()) {
            int sample = Math.min(5, nearbyBusinesses.size());
            log.warn("[COMP-NO-MATCH] property={}: ни один из {} бизнесов не классифицирован. Первые {} для проверки тегов:",
                    property.getId(), nearbyBusinesses.size(), sample);
            for (int i = 0; i < sample; i++) {
                NearbyBusiness b = nearbyBusinesses.get(i);
                log.warn("[COMP-NO-MATCH]   {} → теги: {}", b.name(), b.rubrics());
            }
        }

        int competitorScore;
        if      (direct >= 5)   competitorScore = 0;
        else if (direct >= 3)   competitorScore = 3;
        else if (direct == 2)   competitorScore = 6;
        else if (direct == 1)   competitorScore = 12;
        else if (indirect >= 6) competitorScore = 12;
        else if (indirect >= 3) competitorScore = 18;
        else if (indirect >= 1) competitorScore = 24;
        else                    competitorScore = MAX_COMPETITOR_SCORE;

        int synergyScore;
        List<String> synergyNames = new ArrayList<>();
        if (desiredNeighborIds.isEmpty()) {
            synergyScore = MAX_SYNERGY_SCORE;
        } else {
            int found = synergyByCategory.size();
            synergyScore = (int) Math.round(MAX_SYNERGY_SCORE * (double) found / desiredNeighborIds.size());
            for (List<String> names : synergyByCategory.values()) {
                synergyNames.addAll(names);
            }
        }

        log.info("[SYNERGY] property={}: желаемых соседей={}, найдено категорий={}, соседи={}, балл={}/{}",
                property.getId(), desiredNeighborIds.size(),
                synergyByCategory.size(), synergyNames, synergyScore, MAX_SYNERGY_SCORE);

        return new NeighborhoodResult(competitorScore, directNames, indirectNames,
                                      synergyScore, synergyNames);
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

    private boolean isInRange(BigDecimal value, BigDecimal min, BigDecimal max) {
        if (min != null && value.compareTo(min) < 0) return false;
        if (max != null && value.compareTo(max) > 0) return false;
        return true;
    }

    private int partialScore(BigDecimal value, BigDecimal min, BigDecimal max, int maxPoints) {
        if (min != null && value.compareTo(min) < 0) {
            double ratio = value.doubleValue() / min.doubleValue();
            if (ratio >= 0.8) return (int) Math.round(maxPoints * ratio * 0.5);
        }
        if (max != null && value.compareTo(max) > 0) {
            double ratio = max.doubleValue() / value.doubleValue();
            if (ratio >= 0.8) return (int) Math.round(maxPoints * ratio * 0.5);
        }
        return 0;
    }

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
