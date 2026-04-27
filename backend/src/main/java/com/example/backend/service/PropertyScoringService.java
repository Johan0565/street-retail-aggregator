package com.example.backend.service;

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
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Сервис интеллектуального скоринга помещений.
 *
 * Алгоритм оценивает каждое помещение по 4 компонентам:
 *   - Финансовый мэтч   (0-20 баллов) — площадь и бюджет
 *   - Технический мэтч  (0-40 баллов) — критичные требования бизнеса
 *   - Локация/синергия  (0-25 баллов) — расстояние и желаемые соседи
 *   - Конкуренты        (0-15 баллов) — отсутствие прямых конкурентов
 *
 * ИТОГО: 0-100 баллов
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class PropertyScoringService {

    private final GisSearchService gisSearchService;
    private final BusinessCategoryRepository businessCategoryRepository;

    // --- Веса компонентов (в сумме = 100) ---
    private static final int MAX_FINANCIAL_SCORE = 20;
    private static final int MAX_TECHNICAL_SCORE = 40;
    private static final int MAX_LOCATION_SCORE  = 25;
    private static final int MAX_COMPETITOR_SCORE = 15;

    /**
     * Оценить список помещений по профилю поиска и вернуть отсортированный результат.
     */
    public List<ScoredPropertyDto> scoreAndRankProperties(SearchProfile profile, List<Property> properties) {
        return properties.stream()
                .map(property -> scoreProperty(profile, property))
                .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
                .collect(Collectors.toList());
    }

    /**
     * Рассчитать скоринг для одного помещения.
     */
    public ScoredPropertyDto scoreProperty(SearchProfile profile, Property property) {
        int financialScore  = calculateFinancialScore(profile, property);
        int technicalScore  = calculateTechnicalScore(profile, property);
        int locationScore   = calculateLocationScore(profile, property);
        int competitorScore = calculateCompetitorScore(profile, property);

        int total = financialScore + technicalScore + locationScore + competitorScore;

        String matchLabel = resolveMatchLabel(total);
        String matchColor = resolveMatchColor(total);

        log.debug("Property [{}] scored: total={}, financial={}, technical={}, location={}, competitor={}",
                property.getId(), total, financialScore, technicalScore, locationScore, competitorScore);

        return ScoredPropertyDto.builder()
                .property(property)
                .totalScore(total)
                .financialScore(financialScore)
                .technicalScore(technicalScore)
                .locationScore(locationScore)
                .competitorScore(competitorScore)
                .matchLabel(matchLabel)
                .matchColor(matchColor)
                .build();
    }

    // =========================================================================
    //  КОМПОНЕНТ 1: Финансовый мэтч (0-20 баллов)
    //  Оценивает попадание площади и цены в указанный арендатором диапазон.
    // =========================================================================
    private int calculateFinancialScore(SearchProfile profile, Property property) {
        int score = 0;

        // --- Площадь (0-10 баллов) ---
        if (property.getAreaSqm() != null) {
            boolean areaOk = isInRange(property.getAreaSqm(), profile.getMinArea(), profile.getMaxArea());
            if (areaOk) {
                score += 10;
            } else {
                // Частичный балл, если выходит за диапазон не более чем на 20%
                score += partialScore(property.getAreaSqm(), profile.getMinArea(), profile.getMaxArea(), 10);
            }
        }

        // --- Бюджет (0-10 баллов) ---
        if (property.getPricePerMonth() != null) {
            boolean priceOk = isInRange(property.getPricePerMonth(), profile.getMinBudget(), profile.getMaxBudget());
            if (priceOk) {
                score += 10;
            } else {
                score += partialScore(property.getPricePerMonth(), profile.getMinBudget(), profile.getMaxBudget(), 10);
            }
        }

        return Math.min(score, MAX_FINANCIAL_SCORE);
    }

    // =========================================================================
    //  КОМПОНЕНТ 2: Технический мэтч (0-40 баллов)
    //  Каждое критичное требование бизнеса — обязательное условие.
    //  Отсутствие = штраф. Наличие = полный балл.
    // =========================================================================
    private int calculateTechnicalScore(SearchProfile profile, Property property) {
        // 4 критерия по 10 баллов каждый
        int score = MAX_TECHNICAL_SCORE;

        // --- Вода (10 баллов) ---
        if (Boolean.TRUE.equals(profile.getRequiresWater()) && !Boolean.TRUE.equals(property.getHasWater())) {
            score -= 10; // Критическое требование не выполнено
        }

        // --- Вытяжка (10 баллов) ---
        if (Boolean.TRUE.equals(profile.getRequiresVentilation()) && !Boolean.TRUE.equals(property.getHasVentilation())) {
            score -= 10;
        }

        // --- Отдельный вход (10 баллов) ---
        if (Boolean.TRUE.equals(profile.getRequiresSeparateEntrance()) && !Boolean.TRUE.equals(property.getHasSeparateEntrance())) {
            score -= 10;
        }

        // --- Электрическая мощность (10 баллов) ---
        if (profile.getMinPowerKw() != null && profile.getMinPowerKw() > 0) {
            int propertyPower = property.getPowerKw() != null ? property.getPowerKw() : 0;
            if (propertyPower < profile.getMinPowerKw()) {
                score -= 10;
            }
        }

        return Math.max(score, 0);
    }

    // =========================================================================
    //  КОМПОНЕНТ 3: Локация и синергия (0-25 баллов)
    //  15 баллов — расстояние от центра поиска
    //  10 баллов — наличие желаемых соседей в здании
    // =========================================================================
    private int calculateLocationScore(SearchProfile profile, Property property) {
        int score = 0;

        // --- Расстояние (0-15 баллов) ---
        if (profile.getCenterLatitude() != null && profile.getCenterLongitude() != null
                && property.getLatitude() != null && property.getLongitude() != null) {

            double distanceMeters = haversineDistanceMeters(
                    profile.getCenterLatitude().doubleValue(),
                    profile.getCenterLongitude().doubleValue(),
                    property.getLatitude().doubleValue(),
                    property.getLongitude().doubleValue()
            );

            int radius = profile.getSearchRadiusMeters() != null ? profile.getSearchRadiusMeters() : 5000;

            if (distanceMeters <= radius * 0.33) {
                score += 15; // В пределах 1/3 радиуса — максимум
            } else if (distanceMeters <= radius * 0.66) {
                score += 10; // В пределах 2/3 радиуса
            } else if (distanceMeters <= radius) {
                score += 5;  // В пределах радиуса
            }
            // За пределами радиуса — 0 баллов
        } else {
            // Если координаты не заданы, локация не учитывается — даём половину баллов
            score += 8;
        }

        // --- Синергичные соседи (0-10 баллов) ---
        Set<BusinessCategory> desiredNeighbors = profile.getDesiredNeighbors();
        Set<BusinessCategory> existingNeighbors = property.getExistingNeighbors();

        if (desiredNeighbors != null && !desiredNeighbors.isEmpty()
                && existingNeighbors != null && !existingNeighbors.isEmpty()) {

            long matches = desiredNeighbors.stream()
                    .filter(desired -> existingNeighbors.stream()
                            .anyMatch(existing -> existing.getId().equals(desired.getId())))
                    .count();

            // Пропорциональный балл: нашли всех желаемых соседей — максимум
            int synergyScore = (int) Math.round((double) matches / desiredNeighbors.size() * 10);
            score += synergyScore;
        }

        return Math.min(score, MAX_LOCATION_SCORE);
    }

    // =========================================================================
    //  КОМПОНЕНТ 4: Анализ конкурентов (0-15 баллов)
    //  Если в здании уже есть конкурент (та же категория) — штраф.
    //  Нет конкурентов — максимальный балл.
    // =========================================================================
    private int calculateCompetitorScore(SearchProfile profile, Property property) {
        if (profile.getBusinessCategory() == null) {
            return MAX_COMPETITOR_SCORE; // Категория не задана — конкурентов нет
        }

        Set<BusinessCategory> existingNeighbors = property.getExistingNeighbors();
        if (existingNeighbors == null || existingNeighbors.isEmpty()) {
            return MAX_COMPETITOR_SCORE; // В здании нет зарегистрированных соседей
        }

        Long targetCategoryId = profile.getBusinessCategory().getId();

        // Проверяем прямых конкурентов (та же категория)
        boolean hasDirectCompetitor = existingNeighbors.stream()
                .anyMatch(neighbor -> neighbor.getId().equals(targetCategoryId));

        // Проверяем косвенных конкурентов (та же родительская категория)
        boolean hasIndirectCompetitor = !hasDirectCompetitor && existingNeighbors.stream()
                .anyMatch(neighbor -> neighbor.getParentCategory() != null
                        && profile.getBusinessCategory().getParentCategory() != null
                        && neighbor.getParentCategory().getId().equals(
                                profile.getBusinessCategory().getParentCategory().getId()));

        if (hasDirectCompetitor) {
            return 0; // Прямой конкурент — максимальный штраф
        } else if (hasIndirectCompetitor) {
            return MAX_COMPETITOR_SCORE / 2; // Косвенный конкурент — половина штрафа
        } else {
            return MAX_COMPETITOR_SCORE; // Нет конкурентов — максимум
        }
    }

    // =========================================================================
    //  ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
    // =========================================================================

    /**
     * Формула Haversine — расстояние между двумя точками на сфере в метрах.
     */
    private double haversineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
        final int EARTH_RADIUS_METERS = 6_371_000;

        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);

        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);

        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_METERS * c;
    }

    /**
     * Проверяет, попадает ли значение в диапазон [min, max].
     * Если граница не задана (null) — считается «бесконечной».
     */
    private boolean isInRange(BigDecimal value, BigDecimal min, BigDecimal max) {
        if (min != null && value.compareTo(min) < 0) return false;
        if (max != null && value.compareTo(max) > 0) return false;
        return true;
    }

    /**
     * Частичный балл при небольшом выходе за диапазон (до 20% от границы).
     * Возвращает 0, если выход за диапазон более 20%.
     */
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

    /**
     * Текстовая метка мэтча по итоговому баллу.
     */
    private String resolveMatchLabel(int score) {
        if (score >= 75) return "🔥 Отличный мэтч!";
        if (score >= 50) return "👍 Хороший вариант";
        if (score >= 25) return "⚠️ Частичное совпадение";
        return "❌ Не подходит";
    }

    /**
     * Цвет для отображения на карте и UI.
     */
    private String resolveMatchColor(int score) {
        if (score >= 75) return "green";
        if (score >= 50) return "yellow";
        return "red";
    }

    // =========================================================================
    //  СКОРИНГ С РЕАЛЬНЫМИ ДАННЫМИ 2GIS (для карточки объекта)
    // =========================================================================

    /**
     * Рассчитать скоринг для одного помещения с запросом реальных данных о
     * конкурентах через 2GIS Places API. Использует кэш результатов 2GIS.
     */
    public ScoredPropertyDto scorePropertyWithGis(SearchProfile profile, Property property) {
        List<BusinessCategory> allCategories = businessCategoryRepository.findAll();

        int financialScore  = calculateFinancialScore(profile, property);
        int technicalScore  = calculateTechnicalScore(profile, property);
        int locationScore   = calculateLocationScore(profile, property);
        int competitorScore = calculateCompetitorScoreWithGis(profile, property, allCategories);

        int total = financialScore + technicalScore + locationScore + competitorScore;

        log.debug("GIS-scoring property [{}]: total={}, financial={}, technical={}, location={}, competitor={}",
                property.getId(), total, financialScore, technicalScore, locationScore, competitorScore);

        return ScoredPropertyDto.builder()
                .property(property)
                .totalScore(total)
                .financialScore(financialScore)
                .technicalScore(technicalScore)
                .locationScore(locationScore)
                .competitorScore(competitorScore)
                .matchLabel(resolveMatchLabel(total))
                .matchColor(resolveMatchColor(total))
                .build();
    }

    /**
     * Компонент конкурентов на основе реальных данных 2GIS.
     *
     * Шкала:
     *   0 прямых конкурентов, 0 косвенных → 15 баллов
     *   0 прямых, есть косвенные          → 8–12 баллов
     *   1 прямой конкурент                → 6 баллов
     *   2 прямых конкурента               → 3 балла
     *   3+ прямых конкурентов             → 0 баллов
     */
    private int calculateCompetitorScoreWithGis(SearchProfile profile, Property property,
                                                List<BusinessCategory> allCategories) {
        if (profile.getBusinessCategory() == null
                || property.getLatitude() == null
                || property.getLongitude() == null) {
            return MAX_COMPETITOR_SCORE;
        }

        int radius = profile.getSearchRadiusMeters() != null
                ? Math.min(profile.getSearchRadiusMeters(), 5000)
                : 1000;

        List<String> nearbyRubrics = gisSearchService.getNearbyRubricNames(
                property.getLatitude().doubleValue(),
                property.getLongitude().doubleValue(),
                radius);

        if (nearbyRubrics.isEmpty()) {
            return MAX_COMPETITOR_SCORE;
        }

        BusinessCategory target = profile.getBusinessCategory();
        long direct = 0;
        long indirect = 0;

        for (String rubric : nearbyRubrics) {
            BusinessCategory matched = matchRubricToCategory(rubric, allCategories);
            if (matched == null) continue;

            if (matched.getId().equals(target.getId())) {
                direct++;
            } else if (matched.getParentCategory() != null
                    && target.getParentCategory() != null
                    && matched.getParentCategory().getId().equals(target.getParentCategory().getId())) {
                indirect++;
            }
        }

        log.debug("Конкуренты вблизи property [{}]: прямых={}, косвенных={}", property.getId(), direct, indirect);

        if (direct >= 3) return 0;
        if (direct == 2) return 3;
        if (direct == 1) return 6;
        if (indirect >= 3) return 8;
        if (indirect >= 1) return 12;
        return MAX_COMPETITOR_SCORE;
    }

    /**
     * Сопоставляет название рубрики 2GIS с нашей категорией бизнеса.
     * Использует word-boundary матч для однословных ключевых слов и
     * substring-матч для многословных.
     */
    private BusinessCategory matchRubricToCategory(String rubricName, List<BusinessCategory> categories) {
        String lowerRubric = rubricName.toLowerCase();
        // Набор слов из названия рубрики (без знаков пунктуации)
        Set<String> rubricWords = new HashSet<>(
                Arrays.asList(lowerRubric.replaceAll("[^а-яёa-z0-9\\s]", " ").trim().split("\\s+"))
        );

        for (BusinessCategory cat : categories) {
            if (cat.getTwoGisKeywords() == null || cat.getTwoGisKeywords().isBlank()) continue;

            for (String kw : cat.getTwoGisKeywords().toLowerCase().split(",")) {
                kw = kw.trim();
                if (kw.isEmpty()) continue;

                boolean matches;
                if (kw.contains(" ")) {
                    // Многословное ключевое слово: проверяем вхождение подстроки
                    matches = lowerRubric.contains(kw);
                } else {
                    // Однословное: точное совпадение слова (предотвращает "бар" → "барбершоп")
                    matches = rubricWords.contains(kw);
                }

                if (matches) return cat;
            }
        }
        return null;
    }
}
