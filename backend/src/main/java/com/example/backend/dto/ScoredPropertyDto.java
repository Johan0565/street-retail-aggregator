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

    private Property property;       // Само помещение

    private int totalScore;          // Итоговый балл 0-100

    // Детализация по компонентам
    private int financialScore;      // 0-20 (площадь + бюджет)
    private int technicalScore;      // 0-40 (вода, вытяжка, кВт, вход)
    private int locationScore;       // 0-25 (расстояние + синергичные соседи)
    private int competitorScore;     // 0-15 (отсутствие конкурентов)

    private String matchLabel;       // "🔥 Отличный мэтч!", "👍 Хороший вариант", "⚠️ Не подходит"
    private String matchColor;       // "green", "yellow", "red" — для UI
    private Long profileId;          // ID проекта поиска
}
