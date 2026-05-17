package com.example.backend.service;

/**
 * Остановка общественного транспорта из OSM. Тип определяется по приоритету
 * OSM-тегов: метро/электричка ценнее автобуса для retail-трафика, поэтому
 * скоринг умножает «эффективное расстояние» автобуса на пенальти-фактор.
 */
public record TransportStop(String name, TransportType type, double lat, double lon) {

    public enum TransportType {
        /** Метро — самый ценный сигнал для розничной точки. */
        METRO(1.0),
        /** Электричка/жд-станция — близко по ценности к метро. */
        RAIL(1.1),
        /** Трамвай — стабильный трафик, чуть мягче. */
        TRAM(1.4),
        /** Автобус/маршрутка — менее ценный, нужно быть ближе. */
        BUS(2.0);

        /** Множитель эффективной дистанции: для автобуса 200м ≈ метро 400м. */
        private final double distancePenalty;

        TransportType(double distancePenalty) {
            this.distancePenalty = distancePenalty;
        }

        public double getDistancePenalty() {
            return distancePenalty;
        }
    }
}
