package com.example.backend.repository;

import com.example.backend.entity.PropertyScoreSnapshot;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PropertyScoreSnapshotRepository extends JpaRepository<PropertyScoreSnapshot, Long> {

    /**
     * Поиск актуальной оценки. profileId передаём как nullable: для
     * запросов «без профиля» (легаси/будущие use-case'ы) нужен отдельный
     * метод, но в текущем API скоринг всегда привязан к профилю.
     */
    Optional<PropertyScoreSnapshot> findByPropertyIdAndProfileIdAndAlgorithmVersion(
            Long propertyId, Long profileId, String algorithmVersion);

    /**
     * Bulk-загрузка для батч-скоринга списка помещений под один профиль:
     * вместо N запросов по одному делаем один IN-запрос. Эта оптимизация
     * критична для getRecommendedPropertiesForTenant — у активного пользователя
     * там 50+ помещений.
     */
    @Query("SELECT s FROM PropertyScoreSnapshot s WHERE s.profileId = :profileId AND s.algorithmVersion = :ver AND s.propertyId IN :propertyIds")
    List<PropertyScoreSnapshot> findAllForBatch(
            @Param("profileId") Long profileId,
            @Param("ver") String algorithmVersion,
            @Param("propertyIds") List<Long> propertyIds);

    /**
     * Инвалидация snapshot'ов конкретного помещения — вызывается, когда
     * landlord меняет цену/характеристики (см. PropertyService.updateProperty).
     * Без этого арендатор увидит устаревшую оценку.
     */
    @Modifying
    @Query("DELETE FROM PropertyScoreSnapshot s WHERE s.propertyId = :propertyId")
    int deleteByPropertyId(@Param("propertyId") Long propertyId);

    /**
     * Инвалидация snapshot'ов конкретного профиля — вызывается, когда
     * арендатор меняет критерии поиска. Без этого арендатор увидит оценку
     * под старые критерии.
     */
    @Modifying
    @Query("DELETE FROM PropertyScoreSnapshot s WHERE s.profileId = :profileId")
    int deleteByProfileId(@Param("profileId") Long profileId);

    /**
     * Удаление snapshot'ов от устаревшей версии алгоритма. Запускается
     * автоматически на старте PropertyScoreSnapshotService (см. cleanup).
     */
    @Modifying
    @Query("DELETE FROM PropertyScoreSnapshot s WHERE s.algorithmVersion <> :currentVersion")
    int deleteByOldAlgorithmVersion(@Param("currentVersion") String currentVersion);
}
