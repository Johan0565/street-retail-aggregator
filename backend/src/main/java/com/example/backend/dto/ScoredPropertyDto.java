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
    private int competitorScore;  // 0-50 (анализ конкурентов через 2GIS)

    private String matchLabel;    // "🔥 Отличный мэтч!", "👍 Хороший вариант", ...
    private String matchColor;    // "green", "yellow", "red"

    // Имена конкурентов, выявленных 2GIS-анализом
    @Builder.Default
    private List<String> directCompetitorNames   = List.of(); // та же категория бизнеса
    @Builder.Default
    private List<String> indirectCompetitorNames = List.of(); // смежная категория
}
