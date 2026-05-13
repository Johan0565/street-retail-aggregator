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
 * Скоринг помещений по трём компонентам (итого 0-100 баллов):
 *
 *   Финансовый мэтч   0-30  — площадь и бюджет
 *   Технический мэтч  0-20  — 8 критериев: вода, вытяжка, вход, мощность,
 *                             санузел, парковка, зона разгрузки, потолки + ремонт
 *   Конкуренты        0-50  — реальные данные 2GIS о конкурентах в радиусе
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class PropertyScoringService {

    private final GisSearchService gisSearchService;
    private final BusinessCategoryRepository businessCategoryRepository;

    private static final int MAX_FINANCIAL_SCORE   = 30;
    private static final int MAX_TECHNICAL_SCORE   = 20;
    private static final int MAX_COMPETITOR_SCORE  = 30;
    private static final int MAX_SYNERGY_SCORE     = 20;

    // =========================================================================
    //  ПУБЛИЧНЫЕ МЕТОДЫ
    // =========================================================================

    /**
     * Оценить и отсортировать список помещений для рекомендательного экрана.
     * Категории загружаются один раз, 2GIS-ответы кэшируются по локации.
     */
    public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
        List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
        return properties.stream()
                .map(p -> scoreInternal(profile, p, allCategories))
                .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
                .collect(Collectors.toList());
    }

    /**
     * Оценить одно помещение (используется на экране карточки объекта).
     */
    public ScoredPropertyDto scorePropertyWithGis(SearchProfile profile, Property property) {
        List<BusinessCategory> allCategories = businessCategoryRepository.findAll();
        return scoreInternal(profile, property, allCategories);
    }

    // =========================================================================
    //  ЕДИНЫЙ ВНУТРЕННИЙ SCORER
    // =========================================================================

    private ScoredPropertyDto scoreInternal(SearchProfile profile, Property property,
                                             List<BusinessCategory> allCategories) {
        int financial = calculateFinancialScore(profile, property);
        int technical = calculateTechnicalScore(profile, property);
        NeighborhoodResult neighborhood = analyzeNeighborhood(profile, property, allCategories);
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
    //  КОМПОНЕНТ 1: Финансовый мэтч (0-30 баллов)
    //  Площадь (0-15) + Бюджет (0-15)
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
    //  КОМПОНЕНТ 2: Технический мэтч (0-20 баллов)
    //
    //  Штрафная модель: начинаем с 20, вычитаем за несоответствия.
    //  Штрафы за "требуемые" опции срабатывают только если арендатор явно требует.
    //  Штраф за SHELL_AND_CORE — безусловный (объективная характеристика).
    //
    //  Вода (обяз.)          -4
    //  Вытяжка (обяз.)       -4
    //  Отд. вход (обяз.)     -3
    //  Мощность (обяз.)      -3
    //  Санузел (обяз.)       -3
    //  Парковка (обяз.)      -2
    //  Зона разгрузки (обяз.)-2
    //  Потолки (обяз.)       -2
    //  Черновой ремонт       -1  (всегда)
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

        // Безусловный штраф за черновое состояние
        if (property.getRepairState() == RepairState.SHELL_AND_CORE) score -= 1;

        return Math.max(score, 0);
    }

    // =========================================================================
    //  КОМПОНЕНТ 3 + 4: Анализ окрестности через 2GIS
    //
    //  Конкуренты (0-30 баллов) — пересмотренная шкала:
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
    //  Синергия (0-20 баллов) — соседство с желаемыми бизнесами:
    //    Если в профиле задано K желаемых категорий-соседей и среди nearby-
    //    бизнесов представлены F из K — балл = round(20 * F / K).
    //    Если профиль не задаёт желаемых соседей — балл максимальный (20),
    //    чтобы не штрафовать за неуказанные предпочтения.
    // =========================================================================

    private record NeighborhoodResult(
            int competitorScore,
            List<String> directNames,
            List<String> indirectNames,
            int synergyScore,
            List<String> synergyNames
    ) {}

    private NeighborhoodResult analyzeNeighborhood(SearchProfile profile, Property property,
                                                    List<BusinessCategory> allCategories) {
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
        Long targetParentId = target.getParentCategory() != null
                ? target.getParentCategory().getId()
                : null;

        log.info("[COMP-CTX] property={} profile={} (id={}) targetCategory={} (id={}, parentId={}) keywords=[{}]",
                property.getId(),
                profile.getName(), profile.getId(),
                target.getName(), target.getId(), targetParentId,
                target.getTwoGisKeywords());

        List<NearbyBusiness> nearbyBusinesses = gisSearchService.getNearbyBusinesses(
                property.getLatitude().doubleValue(),
                property.getLongitude().doubleValue(),
                radius);

        // Множество ID желаемых категорий-соседей (синергия).
        Set<Long> desiredNeighborIds = new HashSet<>();
        if (profile.getDesiredNeighbors() != null) {
            for (BusinessCategory bc : profile.getDesiredNeighbors()) {
                desiredNeighborIds.add(bc.getId());
            }
        }

        if (nearbyBusinesses.isEmpty()) {
            int synergyEmpty = desiredNeighborIds.isEmpty() ? MAX_SYNERGY_SCORE : 0;
            return new NeighborhoodResult(MAX_COMPETITOR_SCORE, List.of(), List.of(),
                                          synergyEmpty, List.of());
        }

        long direct   = 0;
        long indirect = 0;
        List<String> directNames   = new ArrayList<>();
        List<String> indirectNames = new ArrayList<>();

        // Какие из желаемых категорий найдены и какие соседи к ним относятся.
        Map<Long, List<String>> synergyByCategory = new LinkedHashMap<>();

        // Де-дупликация: одно заведение → максимум +1 к одному счётчику (конкуренты),
        // и не больше одной отметки на каждую desired-категорию (синергия).
        for (NearbyBusiness business : nearbyBusinesses) {
            boolean isDirect   = false;
            boolean isIndirect = false;
            Set<Long> synergyMatchesForBusiness = new HashSet<>();

            for (String rubric : business.rubrics()) {
                BusinessCategory matched = matchRubricToCategory(rubric, allCategories);
                if (matched == null) continue;

                if (!isDirect && matched.getId().equals(target.getId())) {
                    isDirect = true;
                }
                if (!isIndirect && !isDirect
                        && targetParentId != null
                        && matched.getParentCategory() != null
                        && matched.getParentCategory().getId().equals(targetParentId)) {
                    isIndirect = true;
                }
                if (desiredNeighborIds.contains(matched.getId())) {
                    synergyMatchesForBusiness.add(matched.getId());
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
            log.warn("[COMP-NO-MATCH] property={}: ни один из {} бизнесов не классифицирован. Первые {} для проверки рубрик:",
                    property.getId(), nearbyBusinesses.size(), sample);
            for (int i = 0; i < sample; i++) {
                NearbyBusiness b = nearbyBusinesses.get(i);
                log.warn("[COMP-NO-MATCH]   {} → рубрики: {}", b.name(), b.rubrics());
            }
        }

        // Конкурентный балл (0-30).
        int competitorScore;
        if      (direct >= 5)   competitorScore = 0;
        else if (direct >= 3)   competitorScore = 3;
        else if (direct == 2)   competitorScore = 6;
        else if (direct == 1)   competitorScore = 12;
        else if (indirect >= 6) competitorScore = 12;
        else if (indirect >= 3) competitorScore = 18;
        else if (indirect >= 1) competitorScore = 24;
        else                    competitorScore = MAX_COMPETITOR_SCORE;

        // Синергический балл (0-20).
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

    /**
     * Сопоставляет рубрику 2GIS с категорией из нашего справочника.
     * Однословные ключевые слова — word-boundary (предотвращает "бар" → "барбершоп").
     * Многословные — substring-матч.
     */
    private BusinessCategory matchRubricToCategory(String rubricName, List<BusinessCategory> categories) {
        String lowerRubric = rubricName.toLowerCase();
        Set<String> rubricWords = new HashSet<>(
                Arrays.asList(lowerRubric.replaceAll("[^а-яёa-z0-9\\s]", " ").trim().split("\\s+"))
        );

        for (BusinessCategory cat : categories) {
            if (cat.getTwoGisKeywords() == null || cat.getTwoGisKeywords().isBlank()) continue;

            for (String kw : cat.getTwoGisKeywords().toLowerCase().split(",")) {
                kw = kw.trim();
                if (kw.isEmpty()) continue;

                boolean matches = kw.contains(" ")
                        ? lowerRubric.contains(kw)
                        : rubricWords.contains(kw);

                if (matches) return cat;
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

    /** Частичный балл при выходе за диапазон не более чем на 20%. */
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
