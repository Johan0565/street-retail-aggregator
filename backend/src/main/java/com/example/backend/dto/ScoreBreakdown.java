package com.example.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Структурированная разбивка скоринга для UI/AI: позволяет фронту показать
 * tooltip «откуда такой балл» без обращения к LLM. Каждый блок отражает
 * соответствующий компонент {@link ScoredPropertyDto}.
 *
 * Все числовые поля округляются до double вместо int — UI может показывать
 * как «8.4/10» (без округления до 8) или агрегировать в проценты.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ScoreBreakdown {

    private FinancialPart financial;
    private TechnicalPart technical;
    private CompetitorPart competitor;
    private SynergyPart synergy;
    private TransportPart transport;

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class FinancialPart {
        private double budgetPoints;    // 0–10
        private String budgetReason;    // «в бюджете», «выше max на 18%»
        private double areaPoints;      // 0–10
        private String areaReason;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class TechnicalPart {
        /** Каждая строка — отдельный штраф/требование, отражённое в балле. */
        private List<TechnicalItem> items;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class TechnicalItem {
        private String requirement;  // «вода», «мощность», «потолки»
        private double penalty;      // 0 если ок, иначе сколько вычли
        private String reason;       // «отсутствует», «не указано», «дефицит 33%»
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class CompetitorPart {
        private double weightedDirect;
        private double weightedIndirect;
        /** Сортировка — ближайшие первыми (по убыванию веса). */
        private List<CompetitorRef> directRefs;
        private List<CompetitorRef> indirectRefs;
        private int totalNearbyBusinesses;
        private int radiusMeters;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class CompetitorRef {
        private String name;
        private double distanceMeters;
        private double weight;       // 0–1, exp(-d/σ)
        // Координаты POI: фронт использует их, чтобы переместить камеру на
        // выбранный из списка объект. null, если у бизнеса нет координат.
        private Double latitude;
        private Double longitude;
        // Сколько баллов этот конкретный конкурент «съел» из competitorScore.
        // Отрицательное (или 0). Считается как разница между текущим score и
        // тем, что был бы без этого бизнеса.
        private double scoreImpact;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class SynergyPart {
        private int desiredCategoriesCount;
        private int foundCategoriesCount;
        private List<SynergyRef> refs;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class SynergyRef {
        private String name;
        private double distanceMeters;
        private double weight;
        // Координаты POI — для перехода к нему по тапу в списке.
        private Double latitude;
        private Double longitude;
        // Сколько баллов этот сосед добавил в synergyScore (положительное
        // или 0). Соседи, не выигравшие ни одной категории, имеют 0 — они
        // в списке для информации, но в формулу не вошли.
        private double scoreImpact;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class TransportPart {
        private String nearestName;
        private String nearestType;       // METRO / RAIL / TRAM / BUS / NONE
        private double nearestDistanceMeters;  // -1 если ничего не найдено
        private String reason;            // «метро в 220м», «нет общественного транспорта в радиусе»
    }
}
