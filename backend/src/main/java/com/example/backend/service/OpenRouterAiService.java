package com.example.backend.service;

import com.example.backend.dto.ScoreExplainResponse;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.Property;
import com.example.backend.entity.enums.RepairState;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

@Service
@Slf4j
@RequiredArgsConstructor
public class OpenRouterAiService {

    private static final String MODEL     = "openrouter/free";
    private static final int    MAX_TOKENS = 350;

    // Spring сопоставит bean "openRouterRestClient" с полем по имени
    private final RestClient openRouterRestClient;
    private final ObjectMapper objectMapper;

    public ScoreExplainResponse explainScore(ScoredPropertyDto scored) {
        String prompt  = buildSystemPrompt(scored);
        String rawBody = buildRequestBody(prompt);

        try {
            String response = openRouterRestClient.post()
                    .uri("/chat/completions")
                    .header("Content-Type", "application/json")
                    .body(rawBody)
                    .retrieve()
                    .body(String.class);

            JsonNode root    = objectMapper.readTree(response);
            String   content = root.path("choices").path(0)
                                   .path("message").path("content").asText("");

            if (content.isBlank()) {
                log.warn("[AI] OpenRouter вернул пустой ответ. Raw: {}", response);
                return fallback();
            }
            log.info("[AI] Объяснение сформировано ({} символов)", content.length());
            return new ScoreExplainResponse(content.trim());

        } catch (Exception e) {
            log.warn("[AI] Ошибка вызова OpenRouter: {}", e.getMessage());
            return fallback();
        }
    }

    // -------------------------------------------------------------------------

    private String buildSystemPrompt(ScoredPropertyDto scored) {
        Property p = scored.getProperty();

        return """
                ЯЗЫК ОТВЕТА: ТОЛЬКО РУССКИЙ. Отвечай исключительно на русском языке — это обязательное требование.

                Ты — профессиональный AI-помощник по коммерческой недвижимости.
                Твоя задача: объяснить арендатору, почему помещение получило такую оценку.

                ПРАВИЛО: опирайся ИСКЛЮЧИТЕЛЬНО на данные ниже. Не придумывай факты.
                Не используй вводных слов («Конечно!», «Отлично!»). Только деловой стиль, только русский язык.

                🏢 ПОМЕЩЕНИЕ
                Адрес: %s
                Площадь: %s м²   |   Цена: %s ₽/мес   |   Мощность: %s кВт   |   Потолки: %s м
                Ремонт: %s
                Удобства: вода — %s, вытяжка — %s, отдельный вход — %s, санузел — %s, парковка — %s, зона разгрузки — %s

                📊 ОЦЕНКА АЛГОРИТМА
                • Финансовый мэтч (площадь + бюджет): %d/30 баллов
                • Технический мэтч (оборудование + удобства): %d/20 баллов
                • Конкурентный анализ (данные 2GIS в радиусе поиска): %d/50 баллов
                • ИТОГО: %d/100 — %s

                Напиши 3–4 предложения: что конкретно хорошо подходит, что не совпадает с требованиями, стоит ли рассматривать это помещение. Без списков и маркеров — сплошной текст.
                """.formatted(
                nvl(p.getAddress()),
                nvl(p.getAreaSqm()),
                nvl(p.getPricePerMonth()),
                nvl(p.getPowerKw()),
                nvl(p.getCeilingHeight()),
                translateRepair(p.getRepairState()),
                yn(p.getHasWater()), yn(p.getHasVentilation()), yn(p.getHasSeparateEntrance()),
                yn(p.getHasWc()), yn(p.getHasParking()), yn(p.getHasLoadingZone()),
                scored.getFinancialScore(), scored.getTechnicalScore(),
                scored.getCompetitorScore(), scored.getTotalScore(), scored.getMatchLabel()
        );
    }

    private String buildRequestBody(String systemPrompt) {
        try {
            ObjectNode root = objectMapper.createObjectNode();
            root.put("model", MODEL);
            root.put("temperature", 0.1);
            root.put("max_tokens", MAX_TOKENS);

            ArrayNode messages = root.putArray("messages");
            messages.addObject().put("role", "system").put("content", systemPrompt);
            messages.addObject().put("role", "user").put("content",
                    "Объясни оценку этого помещения. Отвечай строго на русском языке.");

            return objectMapper.writeValueAsString(root);
        } catch (Exception e) {
            throw new RuntimeException("Ошибка сборки запроса к OpenRouter", e);
        }
    }

    // -------------------------------------------------------------------------

    private String translateRepair(RepairState state) {
        if (state == null) return "не указано";
        return switch (state) {
            case PRE_FINISHING  -> "под чистовую";
            case TYPICAL        -> "типовой";
            case DESIGNER       -> "дизайнерский";
            case SHELL_AND_CORE -> "требует ремонта";
        };
    }

    private String yn(Boolean value)  { return Boolean.TRUE.equals(value) ? "есть" : "нет"; }
    private String nvl(Object value)  { return value != null ? value.toString() : "не указано"; }

    private ScoreExplainResponse fallback() {
        return new ScoreExplainResponse("AI-анализ временно недоступен. Оценку можно интерпретировать по шкале баллов самостоятельно.");
    }
}
