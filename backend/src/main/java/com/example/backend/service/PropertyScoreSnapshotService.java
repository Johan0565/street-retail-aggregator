package com.example.backend.service;

import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyScoreSnapshot;
import com.example.backend.entity.SearchProfile;
import com.example.backend.repository.PropertyScoreSnapshotRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Кэширующая обёртка вокруг {@link PropertyScoringService}: оценки
 * сохраняются в БД и переиспользуются, пока «свежие» по TTL и совпадают
 * с текущей версией алгоритма.
 *
 * Что это даёт:
 *  - <b>Скорость.</b> Открытие списка/карточки не делает Overpass-запрос,
 *    если snapshot валидный. Холодный старт сценария «арендатор зашёл,
 *    отскроллил, открыл 5 карточек» — раньше 5 × 30с, теперь 5 × ~10мс.
 *  - <b>Стабильность.</b> Между двумя просмотрами оценка не меняется
 *    (мелкие флуктуации Overpass-выдачи или параллельной обработки
 *    больше не дают разных чисел).
 *  - <b>Атомарная инвалидация.</b> При смене характеристик помещения /
 *    критериев профиля точечно удаляем устаревшие snapshot'ы.
 *  - <b>Версионирование.</b> При деплое со сменой
 *    {@link PropertyScoringService#ALGORITHM_VERSION} все старые snapshot'ы
 *    автоматически очищаются на старте приложения.
 *
 * OVERPASS_UNAVAILABLE НЕ сохраняем: следующий запрос должен попробовать
 * снова, а не возвращать «частичную оценку» из БД часами.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class PropertyScoreSnapshotService {

    private final PropertyScoreSnapshotRepository repository;
    private final PropertyScoringService scoringService;
    private final ObjectMapper objectMapper;

    @Value("${property.score.snapshot.ttl-hours:24}")
    private long ttlHours;

    /**
     * При старте приложения чистим snapshot'ы от старых версий алгоритма.
     * Без этого после деплоя со сменой ALGORITHM_VERSION таблица будет
     * содержать «мёртвые» строки, которые нагружают индекс.
     *
     * Слушаем ApplicationReadyEvent, а не @PostConstruct: на момент @PostConstruct
     * Spring ещё не обернул бин в транзакционный прокси, и @Modifying-запрос
     * падает с TransactionRequiredException.
     */
    @EventListener(ApplicationReadyEvent.class)
    @Transactional
    public void cleanupOnStartup() {
        int removed = repository.deleteByOldAlgorithmVersion(PropertyScoringService.ALGORITHM_VERSION);
        if (removed > 0) {
            log.info("[SCORE-SNAP] Очищено {} snapshot'ов от устаревших версий алгоритма (текущая: {})",
                    removed, PropertyScoringService.ALGORITHM_VERSION);
        }
    }

    /**
     * Главный метод: возвращает оценку из snapshot'a или считает заново.
     *
     * @param force true → игнорировать snapshot и форсировать пересчёт
     *              (для «обновить оценку» кнопки фронта)
     */
    @Transactional
    public ScoredPropertyDto scoreWithSnapshot(SearchProfile profile, Property property, boolean force) {
        Long propertyId = property.getId();
        Long profileId = profile.getId();
        String version = PropertyScoringService.ALGORITHM_VERSION;

        if (!force) {
            Optional<PropertyScoreSnapshot> existing =
                    repository.findByPropertyIdAndProfileIdAndAlgorithmVersion(propertyId, profileId, version);
            if (existing.isPresent() && isFresh(existing.get())) {
                ScoredPropertyDto restored = restoreFromSnapshot(existing.get(), property);
                if (restored != null) {
                    log.debug("[SCORE-SNAP] HIT property={} profile={} (computed {})",
                            propertyId, profileId, existing.get().getComputedAt());
                    return restored;
                }
            }
        }

        ScoredPropertyDto fresh = scoringService.scorePropertyWithGis(profile, property);
        saveSnapshot(propertyId, profileId, fresh);
        return fresh;
    }

    /**
     * Батч-вариант: для списка помещений вытаскиваем все имеющиеся
     * snapshot'ы одним запросом, недостающие считаем через scoringService,
     * сохраняем результаты, возвращаем в порядке убывания балла.
     *
     * Это критическая оптимизация: scoreAndRankProperties для активного
     * арендатора с 50 помещениями в ленте раньше всегда делал 50 Overpass-
     * запросов даже на повторное открытие. Теперь — только для тех,
     * чьи snapshot'ы протухли (по дефолту 24ч).
     */
    @Transactional
    public List<ScoredPropertyDto> scoreBatchWithSnapshot(SearchProfile profile, List<Property> properties, boolean force) {
        if (properties.isEmpty()) return List.of();

        Long profileId = profile.getId();
        String version = PropertyScoringService.ALGORITHM_VERSION;

        Map<Long, Property> byId = properties.stream()
                .collect(Collectors.toMap(Property::getId, p -> p, (a, b) -> a, LinkedHashMap::new));

        Map<Long, ScoredPropertyDto> resolved = new HashMap<>();
        List<Property> toCompute = new ArrayList<>();

        if (force) {
            toCompute.addAll(properties);
        } else {
            List<PropertyScoreSnapshot> existing = repository.findAllForBatch(
                    profileId, version, new ArrayList<>(byId.keySet()));
            Set<Long> resolvedIds = new HashSet<>();
            for (PropertyScoreSnapshot snap : existing) {
                if (!isFresh(snap)) continue;
                Property prop = byId.get(snap.getPropertyId());
                if (prop == null) continue;
                ScoredPropertyDto restored = restoreFromSnapshot(snap, prop);
                if (restored != null) {
                    resolved.put(snap.getPropertyId(), restored);
                    resolvedIds.add(snap.getPropertyId());
                }
            }
            for (Property p : properties) {
                if (!resolvedIds.contains(p.getId())) toCompute.add(p);
            }
        }

        log.info("[SCORE-SNAP] Батч profile={}: {} из {} помещений из snapshot'ов, считаем {}",
                profileId, resolved.size(), properties.size(), toCompute.size());

        if (!toCompute.isEmpty()) {
            // Делегируем в scoringService — там сидит ForkJoinPool на 8 потоков.
            List<ScoredPropertyDto> fresh = scoringService.scoreAndRankProperties(profile, toCompute);
            for (ScoredPropertyDto dto : fresh) {
                resolved.put(dto.getProperty().getId(), dto);
                saveSnapshot(dto.getProperty().getId(), profileId, dto);
            }
        }

        // Возвращаем в порядке исходного списка → сортируем по totalScore.
        return resolved.values().stream()
                .sorted(Comparator.comparingInt(ScoredPropertyDto::getTotalScore).reversed())
                .collect(Collectors.toList());
    }

    /**
     * Точечная инвалидация при изменении помещения. Дешевле, чем «протухло»
     * по TTL: арендатор сразу видит актуальные данные после правки.
     */
    @Transactional
    public void invalidateByProperty(Long propertyId) {
        int removed = repository.deleteByPropertyId(propertyId);
        if (removed > 0) {
            log.info("[SCORE-SNAP] Удалено {} snapshot'ов property={}", removed, propertyId);
        }
    }

    /**
     * Точечная инвалидация при изменении критериев поиска арендатора.
     */
    @Transactional
    public void invalidateByProfile(Long profileId) {
        int removed = repository.deleteByProfileId(profileId);
        if (removed > 0) {
            log.info("[SCORE-SNAP] Удалено {} snapshot'ов profile={}", removed, profileId);
        }
    }

    private boolean isFresh(PropertyScoreSnapshot snap) {
        LocalDateTime cutoff = LocalDateTime.now().minusHours(ttlHours);
        return snap.getComputedAt().isAfter(cutoff);
    }

    /**
     * Восстанавливает DTO из БД. Сохранённый payload — это весь DTO без
     * heavy-поля Property (его подгружаем заново, чтобы получить актуальные
     * картинки/цену из properties-таблицы, на случай если что-то поменялось
     * без инвалидации snapshot'a).
     */
    private ScoredPropertyDto restoreFromSnapshot(PropertyScoreSnapshot snap, Property property) {
        try {
            ScoredPropertyDto dto = objectMapper.readValue(snap.getPayloadJson(), ScoredPropertyDto.class);
            dto.setProperty(property);
            dto.setComputedAt(snap.getComputedAt());
            dto.setAlgorithmVersion(snap.getAlgorithmVersion());
            return dto;
        } catch (Exception e) {
            log.warn("[SCORE-SNAP] Не удалось десериализовать snapshot id={}: {}", snap.getId(), e.getMessage());
            // Битый snapshot — удаляем, чтобы при следующем чтении не зацикливаться.
            evictBroken(snap.getId());
            return null;
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void evictBroken(Long id) {
        repository.deleteById(id);
    }

    /**
     * Сохраняем snapshot. OVERPASS_UNAVAILABLE НЕ сохраняем — это сбойное
     * состояние, следующий запрос должен попробовать снова и получить
     * полную оценку.
     */
    private void saveSnapshot(Long propertyId, Long profileId, ScoredPropertyDto dto) {
        if (dto.getDataStatus() == ScoredPropertyDto.DataStatus.OVERPASS_UNAVAILABLE) return;
        try {
            // Сериализуем без property — оно тяжёлое (картинки, landlord-юзер),
            // и при восстановлении мы всё равно подтягиваем актуальную версию
            // из БД через PropertyRepository.
            ScoredPropertyDto copy = cloneWithoutProperty(dto);
            String json = objectMapper.writeValueAsString(copy);

            String version = PropertyScoringService.ALGORITHM_VERSION;
            Optional<PropertyScoreSnapshot> existing =
                    repository.findByPropertyIdAndProfileIdAndAlgorithmVersion(propertyId, profileId, version);
            PropertyScoreSnapshot snap = existing.orElseGet(() -> PropertyScoreSnapshot.builder()
                    .propertyId(propertyId)
                    .profileId(profileId)
                    .algorithmVersion(version)
                    .build());
            snap.setTotalScore(dto.getTotalScore());
            snap.setFinancialScore(dto.getFinancialScore());
            snap.setTechnicalScore(dto.getTechnicalScore());
            snap.setCompetitorScore(dto.getCompetitorScore());
            snap.setSynergyScore(dto.getSynergyScore());
            snap.setTransportScore(dto.getTransportScore());
            snap.setMatchLabel(dto.getMatchLabel());
            snap.setMatchColor(dto.getMatchColor());
            snap.setDataStatus(dto.getDataStatus().name());
            snap.setPayloadJson(json);
            snap.setComputedAt(LocalDateTime.now());
            repository.save(snap);
        } catch (Exception e) {
            log.warn("[SCORE-SNAP] Ошибка сохранения snapshot property={} profile={}: {}",
                    propertyId, profileId, e.getMessage());
        }
    }

    private ScoredPropertyDto cloneWithoutProperty(ScoredPropertyDto src) {
        return ScoredPropertyDto.builder()
                .property(null)
                .totalScore(src.getTotalScore())
                .financialScore(src.getFinancialScore())
                .technicalScore(src.getTechnicalScore())
                .competitorScore(src.getCompetitorScore())
                .synergyScore(src.getSynergyScore())
                .transportScore(src.getTransportScore())
                .directCompetitorNames(src.getDirectCompetitorNames())
                .synergyNeighborNames(src.getSynergyNeighborNames())
                .matchLabel(src.getMatchLabel())
                .matchColor(src.getMatchColor())
                .breakdown(src.getBreakdown())
                .dataStatus(src.getDataStatus())
                .algorithmVersion(src.getAlgorithmVersion())
                .computedAt(src.getComputedAt())
                .build();
    }
}
