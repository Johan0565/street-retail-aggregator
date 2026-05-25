package com.example.backend.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * Сохранённая оценка помещения под конкретный проект поиска. Решает три
 * задачи сразу:
 *   1. <b>Скорость показа списка</b> — открытие карточки/списка не делает
 *      Overpass-вызовы, если snapshot свежий.
 *   2. <b>Стабильность вывода</b> — одно и то же помещение между двумя
 *      просмотрами не меняет балл (раньше при флуктуациях Overpass-кэша
 *      и параллельной обработке мог давать разные числа).
 *   3. <b>Версионирование алгоритма</b> — поле {@link #algorithmVersion}
 *      позволяет принудительно пересчитать всё, что было оценено до апдейта
 *      формулы скоринга (см. PropertyScoringService.ALGORITHM_VERSION).
 *
 * Уникальный индекс по (propertyId, profileId, algorithmVersion) гарантирует,
 * что под один (property, profile) хранится ровно одна актуальная оценка
 * для текущей версии алгоритма.
 */
@Entity
@Table(name = "property_score_snapshots",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_score_snapshot_property_profile_ver",
                columnNames = {"property_id", "profile_id", "algorithm_version"}),
        indexes = @Index(name = "idx_score_snapshot_lookup",
                columnList = "property_id,profile_id,algorithm_version"))
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PropertyScoreSnapshot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "property_id", nullable = false)
    private Long propertyId;

    /**
     * Профиль поиска, под который оценивали. Может быть null для глобальных
     * оценок (без учёта арендатора), но в текущем API всегда задаётся.
     */
    @Column(name = "profile_id")
    private Long profileId;

    @Column(name = "algorithm_version", nullable = false, length = 16)
    private String algorithmVersion;

    @Column(name = "total_score", nullable = false)
    private int totalScore;

    @Column(name = "financial_score", nullable = false)
    private int financialScore;

    @Column(name = "technical_score", nullable = false)
    private int technicalScore;

    @Column(name = "competitor_score", nullable = false)
    private int competitorScore;

    @Column(name = "synergy_score", nullable = false)
    private int synergyScore;

    @Column(name = "transport_score", nullable = false)
    private int transportScore;

    @Column(name = "match_label", length = 128)
    private String matchLabel;

    @Column(name = "match_color", length = 16)
    private String matchColor;

    @Column(name = "data_status", nullable = false, length = 32)
    private String dataStatus;

    /**
     * Сериализованный ScoredPropertyDto без поля property (его подгружаем
     * заново через PropertyRepository по {@link #propertyId}). Хранит
     * breakdown, directCompetitorNames, synergyNeighborNames — всё, что
     * нужно фронту для отрисовки.
     */
    @Column(name = "payload_json", nullable = false, columnDefinition = "TEXT")
    private String payloadJson;

    @Column(name = "computed_at", nullable = false)
    private LocalDateTime computedAt;
}
