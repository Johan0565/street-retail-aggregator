package com.example.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.concurrent.Executors;

/**
 * HTTP-клиенты для внешних API. Под капотом — {@link HttpClient} из
 * java.net.http (JDK 17+), который держит persistent-соединения, делает
 * HTTP/2-мультиплексирование и переиспользует TLS-сессии. Это устраняет
 * TCP+TLS handshake на каждый запрос — критично для Overpass, потому что
 * скоринг батча из 20 помещений делал 20+ полных handshake'ов на старом
 * {@code SimpleClientHttpRequestFactory}.
 */
@Configuration
public class RestClientConfig {

    /**
     * RestClient для Overpass API. Пул из 16 потоков покрывает 8 параллельных
     * скоринг-нитей × 1 запрос на помещение (после объединения с транспортом)
     * с запасом на ретраи. Connection pool у {@link HttpClient} управляется
     * автоматически и переживает короткие паузы между запросами.
     */
    @Bean
    public RestClient overpassRestClient() {
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .version(HttpClient.Version.HTTP_2)
                .executor(Executors.newFixedThreadPool(16, r -> {
                    Thread t = new Thread(r, "overpass-http");
                    t.setDaemon(true);
                    return t;
                }))
                .build();
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(http);
        // Overpass под нагрузкой штатно отвечает 10–25с — обрезать его жёстче
        // нельзя, иначе он возвращает пустые тела и скоринг выводит нули
        // конкурентов/соседей.
        factory.setReadTimeout(Duration.ofSeconds(30));
        return RestClient.builder()
                .requestFactory(factory)
                .build();
    }

    /**
     * Отдельный клиент для OpenRouter — другая базовая URL, другой таймаут.
     * LLM-стриминг здесь не используется, поэтому keepalive-эффект меньше,
     * но HTTP/2 и pooling всё равно режут несколько сот мс на запрос.
     */
    @Bean
    public RestClient openRouterRestClient(@Value("${openrouter.api.key}") String apiKey) {
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .version(HttpClient.Version.HTTP_2)
                .build();
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(http);
        // DeepSeek V3 free-tier иногда стоит в очереди; для блочного ответа
        // ~900 токенов запас по таймауту — обязателен, иначе будет fallback
        // даже когда модель в итоге отвечает корректно.
        factory.setReadTimeout(Duration.ofSeconds(60));
        return RestClient.builder()
                .requestFactory(factory)
                .baseUrl("https://openrouter.ai/api/v1")
                .defaultHeader("Authorization", "Bearer " + apiKey)
                .build();
    }
}
