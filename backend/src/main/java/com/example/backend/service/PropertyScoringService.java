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
    private static final int MAX_COMPETITOR_SCORE  = 50;

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
        int financial   = calculateFinancialScore(profile, property);
        int technical   = calculateTechnicalScore(profile, property);
        int competitors = calculateCompetitorScore(profile, property, allCategories);
        int total       = financial + technical + competitors;

        log.debug("Scoring [{}]: total={}, fin={}, tech={}, comp={}",
                property.getId(), total, financial, technical, competitors);

        return ScoredPropertyDto.builder()
                .property(property)
                .totalScore(total)
                .financialScore(financial)
                .technicalScore(technical)
                .competitorScore(competitors)
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
    //  КОМПОНЕНТ 3: Анализ конкурентов через 2GIS (0-50 баллов)
    //
    //  Считаем прямых конкурентов (та же категория) и косвенных (та же
    //  родительская категория). Чем больше конкурентов — тем ниже балл.
    //
    //  Прямые  | Косвенные | Балл
    //  ---------|-----------|-----
    //  0        | 0         | 50
    //  0        | 1–2       | 40
    //  0        | 3–5       | 30
    //  0        | 6+        | 20
    //  1        | —         | 20
    //  2        | —         | 10
    //  3–4      | —         |  5
    //  5+       | —         |  0
    // =========================================================================

    private int calculateCompetitorScore(SearchProfile profile, Property property,
                                          List<BusinessCategory> allCategories) {
        if (profile.getBusinessCategory() == null
                || property.getLatitude() == null
                || property.getLongitude() == null) {
            return MAX_COMPETITOR_SCORE;
        }

        int radius = profile.getSearchRadiusMeters() != null
                ? Math.min(profile.getSearchRadiusMeters(), 5000)
                : 1000;

        // Каждый вложенный список — рубрики одного конкретного заведения
        List<List<String>> nearbyBusinesses = gisSearchService.getNearbyRubricNames(
                property.getLatitude().doubleValue(),
                property.getLongitude().doubleValue(),
                radius);

        if (nearbyBusinesses.isEmpty()) {
            return MAX_COMPETITOR_SCORE;
        }

        BusinessCategory target = profile.getBusinessCategory();
        Long targetParentId = target.getParentCategory() != null
                ? target.getParentCategory().getId()
                : null;

        long direct   = 0;
        long indirect = 0;

        // Считаем заведения, а не уникальные рубрики: одно заведение — один конкурент
        for (List<String> businessRubrics : nearbyBusinesses) {
            boolean isDirect   = false;
            boolean isIndirect = false;

            for (String rubric : businessRubrics) {
                BusinessCategory matched = matchRubricToCategory(rubric, allCategories);
                if (matched == null) continue;

                if (matched.getId().equals(target.getId())) {
                    isDirect = true;
                    break; // прямое совпадение — дальше не ищем
                }
                if (targetParentId != null
                        && matched.getParentCategory() != null
                        && matched.getParentCategory().getId().equals(targetParentId)) {
                    isIndirect = true; // продолжаем — может быть прямое совпадение в другой рубрике
                }
            }

            if (isDirect)        direct++;
            else if (isIndirect) indirect++;
        }

        log.info("Конкуренты у property [{}] (радиус {}м): прямых={}, косвенных={}, всего заведений={}",
                property.getId(), radius, direct, indirect, nearbyBusinesses.size());

        if (direct >= 5) return 0;
        if (direct >= 3) return 5;
        if (direct == 2) return 10;
        if (direct == 1) return 20;
        // Нет прямых конкурентов
        if (indirect >= 6) return 20;
        if (indirect >= 3) return 30;
        if (indirect >= 1) return 40;
        return MAX_COMPETITOR_SCORE;
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
