package com.example.backend.service;

import java.util.List;

/**
 * Срез OSM-данных вокруг точки: и бизнесы, и транспортные узлы из одного
 * Overpass-запроса. Отдельный {@link FetchStatus} различает «API отдал
 * пусто, потому что вокруг ничего нет» (OK) и «API упал/таймаут/перебрали
 * все mirror'ы» (FAILED). Это ключевое отличие: при FAILED скорер НЕ
 * должен выставлять max-балл «нет конкурентов = 40/40» — иначе сбой
 * Overpass превращается в ложно-положительную оценку.
 */
public record OverpassAreaSnapshot(
        List<NearbyBusiness> businesses,
        List<TransportStop> transportStops,
        FetchStatus status
) {

    public enum FetchStatus {
        /** HTTP-запрос дошёл, тело распарсилось (даже если elements=0). */
        OK,
        /** Все mirror'ы Overpass отдали ошибку/таймаут/пустое тело. */
        FAILED
    }

    public static OverpassAreaSnapshot failed() {
        return new OverpassAreaSnapshot(List.of(), List.of(), FetchStatus.FAILED);
    }

    public boolean isFailed() {
        return status == FetchStatus.FAILED;
    }
}
