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

    private int financialScore;   // 0-30 (площадь + бюджет)
    private int technicalScore;   // 0-20 (вода, вытяжка, кВт, вход)
    private int competitorScore;  // 0-30 (анализ конкурентов через 2GIS)
    private int synergyScore;     // 0-20 (синергия с желаемыми соседями)

    @Builder.Default
    private List<String> directCompetitorNames   = List.of();
    @Builder.Default
    private List<String> indirectCompetitorNames = List.of();
    @Builder.Default
    private List<String> synergyNeighborNames    = List.of();

    private String matchLabel;    // "🔥 Отличный мэтч!", "👍 Хороший вариант", ...
    private String matchColor;    // "green", "yellow", "red"
}
