package com.example.backend.dto;

import com.example.backend.entity.Property;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ScoredPropertyDto {

    private Property property;

    private int totalScore;       // 0-100

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
}
