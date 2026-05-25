package com.example.backend.dto;

import com.example.backend.entity.Property;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ScoredPropertyDto {

    /**
     * Статус источников данных. {@code OVERPASS_UNAVAILABLE} означает, что
     * все mirror'ы Overpass упали — компоненты конкурентов/синергии/
     * транспорта НЕ посчитаны и НЕ влияют на totalScore (раньше при сбое
     * выставлялся max 40/40, и плохой адрес мог стать «🔥 Отличный мэтч»).
     * Фронт должен показать предупреждение «частичная оценка, попробуйте
     * позже».
     */
    public enum DataStatus { COMPLETE, OVERPASS_UNAVAILABLE }

    private Property property;

    private int totalScore;       // 0-100 (или 0-40 при OVERPASS_UNAVAILABLE)

    private int financialScore;   // 0-20 (площадь + бюджет, асимметричный smooth decay)
    private int technicalScore;   // 0-20 (тех. требования, градиент + null-discount)
    private int competitorScore;  // 0-40 (конкуренты, distance-weighted exp decay)
    private int synergyScore;     // 0-15 (синергия с желаемыми соседями, distance-aware)
    private int transportScore;   // 0-5  (близость метро / транспорта)

    @Builder.Default
    private List<String> directCompetitorNames   = List.of();
    @Builder.Default
    private List<String> synergyNeighborNames    = List.of();

    private String matchLabel;    // "🔥 Отличный мэтч!", "👍 Хороший вариант", ...
    private String matchColor;    // "green", "yellow", "red"

    /** Структурированная разбивка (опционально — может быть null для legacy-кода). */
    private ScoreBreakdown breakdown;

    /**
     * Источник данных. При OVERPASS_UNAVAILABLE totalScore посчитан только
     * по финансам и технике, остальные компоненты обнулены и снабжены
     * соответствующим reason'ом в breakdown.
     */
    @Builder.Default
    private DataStatus dataStatus = DataStatus.COMPLETE;

    /**
     * Когда оценка была посчитана. Заполняется при сохранении snapshot'a
     * в БД, чтобы фронт мог показать «оценено N минут назад / обновить».
     * null для legacy-кода и для batch-результатов в памяти.
     */
    private LocalDateTime computedAt;

    /**
     * Версия алгоритма скоринга, под которую была построена эта оценка.
     * Меняется при изменении формул в {@code PropertyScoringService}; нужна,
     * чтобы при апдейте бэкенда снапшоты со старой версией не выдавались
     * как актуальные (их пересчитают).
     */
    private String algorithmVersion;
}
