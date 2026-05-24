package com.example.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

@Configuration
public class RestClientConfig {

    /**
     * RestClient для Overpass API (OpenStreetMap). Запросы могут быть
     * чуть тяжелее обычных REST-вызовов: сервер Overpass иногда отвечает
     * 5–10 сек при высокой нагрузке, поэтому read timeout щедрый.
     */
    @Bean
    public RestClient overpassRestClient() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(30_000);
        return RestClient.builder()
                .requestFactory(factory)
                .build();
    }

    @Bean
    public RestClient openRouterRestClient(@Value("${openrouter.api.key}") String apiKey) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        // DeepSeek V3 free-tier иногда стоит в очереди; для блочного ответа
        // ~900 токенов запас по таймауту — обязателен, иначе будет fallback
        // даже когда модель в итоге отвечает корректно.
        factory.setReadTimeout(60_000);
        return RestClient.builder()
                .requestFactory(factory)
                .baseUrl("https://openrouter.ai/api/v1")
                .defaultHeader("Authorization", "Bearer " + apiKey)
                .build();
    }
}
