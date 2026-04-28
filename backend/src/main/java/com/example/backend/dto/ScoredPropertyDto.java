package com.example.backend.dto;

import com.example.backend.entity.Property;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

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
}
