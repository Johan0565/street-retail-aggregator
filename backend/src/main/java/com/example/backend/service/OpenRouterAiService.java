package com.example.backend.service;

import com.example.backend.dto.ScoreExplainResponse;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.Property;
import com.example.backend.entity.SearchProfile;
import com.example.backend.entity.enums.RepairState;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

@Service
@Slf4j
@RequiredArgsConstructor
public class OpenRouterAiService {

    private static final String MODEL      = "openrouter/free";
    private static final int    MAX_TOKENS = 700;

    private final RestClient openRouterRestClient;
    private final ObjectMapper objectMapper;

    public ScoreExplainResponse explainScore(ScoredPropertyDto scored, SearchProfile profile) {
        String userPrompt;
        try {
            userPrompt = buildUserPrompt(scored, profile);
            log.debug("[AI] Отправляем в OpenRouter:\n{}", userPrompt);
        } catch (Exception e) {
            log.warn("[AI] Ошибка сборки промпта: {}", e.getMessage(), e);
            return fallback();
        }

        try {
            String rawBody = buildRequestBody(userPrompt);
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

    // =========================================================================
    //  ЕДИНЫЙ USER-ПРОМПТ: правила сверху, факты, образец, задание
    // =========================================================================

    private String buildUserPrompt(ScoredPropertyDto scored, SearchProfile profile) {
        Property p = scored.getProperty();

        String facts = buildFactsheet(scored, profile);

        return """
                Ты пишешь на русском языке деловой отчёт об оценке коммерческого помещения. Тебе даны ФАКТЫ — переформулируй их связным текстом. ИНЫХ ФАКТОВ НЕТ.

                ЖЁСТКИЕ ПРАВИЛА (нарушать нельзя):
                - Только русский язык.
                - Объём: ровно 4–6 предложений, сплошным текстом, без списков, без заголовков, без эмодзи.
                - Запрещено: вводные слова («Конечно», «Отлично», «Рассмотрим»), фразы вида «требует улучшений», «небольшая преимущественность», «относительная позиция», обобщённые оценки без цифр.
                - Запрещено объяснять алгоритм («баллы делятся так-то», «50 это максимум»). Только конкретные цифры из ФАКТОВ.
                - Прямых конкурентов называй ПОИМЁННО — каждого. Косвенных — до 5 по именам, остальных числом.
                - Если в ФАКТАХ написано «прямой конкурент — X», ты ОБЯЗАН упомянуть имя X в ответе.
                - Последнее предложение: «Итог: N/100, главное ограничение — …» или «Итог: N/100, ограничений по данным алгоритма нет».

                ПРИМЕР ХОРОШЕГО ОТВЕТА (на других данных):
                Помещение на ул. Ленина, 5 площадью 80 м² за 200 000 ₽/мес соответствует финансовым требованиям полностью. По технике снято 4 балла: арендатор требовал вытяжку, в помещении её нет. По конкурентам найден один прямой — кофейня «Шоколадница», по шкале это 12/30. Косвенные «Правда Кофе» и «Bodro Coffee» рядом, но на балл не повлияли — учитываются только прямые при их наличии. По синергии нашлись 2 из 3 желаемых соседей: бизнес-центр «Лотос» и коворкинг «WeWork», что даёт 13/20. Итог: 71/100, главное ограничение — соседство с «Шоколадницей».

                ФАКТЫ:
                %s

                Теперь напиши отчёт по этим ФАКТАМ, соблюдая все правила выше. Сразу с первого предложения, без вступления.
                """.formatted(facts);
    }

    // =========================================================================
    //  СБОРКА FACTSHEET
    // =========================================================================

    private String buildFactsheet(ScoredPropertyDto scored, SearchProfile profile) {
        Property p = scored.getProperty();
        StringBuilder sb = new StringBuilder();

        sb.append("Адрес: ").append(nvl(p.getAddress())).append('\n');
        sb.append("Параметры помещения: ").append(nvl(p.getAreaSqm())).append(" м², ")
          .append(nvl(p.getPricePerMonth())).append(" ₽/мес, ")
          .append(nvl(p.getPowerKw())).append(" кВт, потолки ")
          .append(nvl(p.getCeilingHeight())).append(" м, ремонт — ")
          .append(translateRepair(p.getRepairState())).append(".\n");

        sb.append("\nФИНАНСЫ ").append(scored.getFinancialScore()).append("/30:\n");
        sb.append(buildFinancialBreakdown(p, profile));

        sb.append("\nТЕХНИКА ").append(scored.getTechnicalScore()).append("/20:\n");
        sb.append(buildTechnicalBreakdown(p, profile));

        sb.append("\nКОНКУРЕНТЫ ").append(scored.getCompetitorScore()).append("/30:\n");
        sb.append(buildCompetitorBreakdown(scored));

        sb.append("\nСИНЕРГИЯ С СОСЕДЯМИ ").append(scored.getSynergyScore()).append("/20:\n");
        sb.append(buildSynergyBreakdown(scored, profile));

        sb.append("\nИТОГ: ").append(scored.getTotalScore()).append("/100 (")
          .append(nvl(scored.getMatchLabel())).append(").");
        return sb.toString();
    }

    private String buildSynergyBreakdown(ScoredPropertyDto scored, SearchProfile profile) {
        List<String> neighbors = nvlList(scored.getSynergyNeighborNames());
        int desired = (profile == null || profile.getDesiredNeighbors() == null)
                ? 0 : profile.getDesiredNeighbors().size();

        if (desired == 0) {
            return "- арендатор не указывал желаемых соседей; синергический балл максимальный по умолчанию.\n";
        }
        if (neighbors.isEmpty()) {
            return "- желаемых соседей рядом не найдено ни одного из " + desired + " категорий; балл 0/20.\n";
        }
        return "- найдены желаемые соседи (" + neighbors.size() + "): "
                + joinNames(neighbors, 7) + ". Балл " + scored.getSynergyScore() + "/20.\n";
    }

    private String buildFinancialBreakdown(Property p, SearchProfile profile) {
        StringBuilder sb = new StringBuilder();
        if (profile == null) {
            sb.append("- профиль арендатора недоступен.\n");
            return sb.toString();
        }

        BigDecimal area = p.getAreaSqm();
        BigDecimal minA = profile.getMinArea();
        BigDecimal maxA = profile.getMaxArea();
        if (area != null && (minA != null || maxA != null)) {
            String range = formatRange(minA, maxA, "м²");
            if (inRange(area, minA, maxA))
                sb.append("- площадь ").append(area).append(" м² попадает в требуемый диапазон ").append(range).append(".\n");
            else if (minA != null && area.compareTo(minA) < 0)
                sb.append("- площадь ").append(area).append(" м² меньше минимальной ").append(minA).append(" м².\n");
            else if (maxA != null && area.compareTo(maxA) > 0)
                sb.append("- площадь ").append(area).append(" м² больше максимальной ").append(maxA).append(" м².\n");
        }

        BigDecimal price = p.getPricePerMonth();
        BigDecimal minB  = profile.getMinBudget();
        BigDecimal maxB  = profile.getMaxBudget();
        if (price != null && (minB != null || maxB != null)) {
            String range = formatRange(minB, maxB, "₽");
            if (inRange(price, minB, maxB))
                sb.append("- цена ").append(price).append(" ₽/мес укладывается в бюджет ").append(range).append(".\n");
            else if (maxB != null && price.compareTo(maxB) > 0)
                sb.append("- цена ").append(price).append(" ₽/мес выше бюджета (макс. ").append(maxB).append(" ₽).\n");
            else if (minB != null && price.compareTo(minB) < 0)
                sb.append("- цена ").append(price).append(" ₽/мес ниже нижней границы бюджета (").append(minB).append(" ₽).\n");
        }

        if (sb.length() == 0) sb.append("- финансовые требования арендатором не заданы.\n");
        return sb.toString();
    }

    private String buildTechnicalBreakdown(Property p, SearchProfile profile) {
        if (profile == null) return "- профиль арендатора недоступен.\n";

        List<String> penalties = new ArrayList<>();
        addPenalty(penalties, profile.getRequiresWater(),            p.getHasWater(),            "вода",            4);
        addPenalty(penalties, profile.getRequiresVentilation(),      p.getHasVentilation(),      "вытяжка",         4);
        addPenalty(penalties, profile.getRequiresSeparateEntrance(), p.getHasSeparateEntrance(), "отдельный вход",  3);
        addPenalty(penalties, profile.getRequiresWc(),               p.getHasWc(),               "санузел",         3);
        addPenalty(penalties, profile.getRequiresParking(),          p.getHasParking(),          "парковка",        2);
        addPenalty(penalties, profile.getRequiresLoadingZone(),      p.getHasLoadingZone(),      "зона разгрузки",  2);

        if (profile.getMinPowerKw() != null && profile.getMinPowerKw() > 0) {
            int actual = p.getPowerKw() != null ? p.getPowerKw() : 0;
            if (actual < profile.getMinPowerKw())
                penalties.add("- мощности " + actual + " кВт не хватает (требовалось от " + profile.getMinPowerKw() + " кВт), −3.");
        }
        if (profile.getMinCeilingHeight() != null && p.getCeilingHeight() != null
                && p.getCeilingHeight().compareTo(profile.getMinCeilingHeight()) < 0)
            penalties.add("- потолки " + p.getCeilingHeight() + " м ниже требуемых "
                    + profile.getMinCeilingHeight() + " м, −2.");
        if (p.getRepairState() == RepairState.SHELL_AND_CORE)
            penalties.add("- помещение в состоянии \"требует ремонта\", −1.");

        if (penalties.isEmpty())
            return "- помещение полностью отвечает техническим требованиям арендатора.\n";
        return String.join("\n", penalties) + "\n";
    }

    private void addPenalty(List<String> out, Boolean required, Boolean has, String name, int cost) {
        if (Boolean.TRUE.equals(required) && !Boolean.TRUE.equals(has))
            out.add("- арендатор требовал " + name + ", в помещении нет, −" + cost + ".");
    }

    private String buildCompetitorBreakdown(ScoredPropertyDto scored) {
        List<String> direct   = nvlList(scored.getDirectCompetitorNames());
        List<String> indirect = nvlList(scored.getIndirectCompetitorNames());
        int score = scored.getCompetitorScore();
        int penalty = 30 - score;

        StringBuilder sb = new StringBuilder();

        if (direct.isEmpty() && indirect.isEmpty()) {
            sb.append("- в радиусе поиска 2GIS не найдено ни прямых, ни косвенных конкурентов; балл максимальный, 30/30.\n");
            return sb.toString();
        }

        if (!direct.isEmpty()) {
            sb.append("- прямые конкуренты (").append(direct.size()).append("): ")
              .append(joinNames(direct, 10)).append(".\n");
            sb.append("- по шкале: ").append(scaleRowForDirect(direct.size())).append('\n');
        } else {
            sb.append("- прямых конкурентов нет.\n");
        }

        if (!indirect.isEmpty()) {
            sb.append("- косвенные конкуренты (").append(indirect.size()).append("): ")
              .append(joinNames(indirect, 7)).append(".\n");
            if (direct.isEmpty())
                sb.append("- по шкале: ").append(scaleRowForIndirect(indirect.size())).append('\n');
            else
                sb.append("- косвенные на балл не повлияли (учитываются только при отсутствии прямых).\n");
        }

        sb.append("- итог по конкурентам: ").append(score).append("/30, потеряно ").append(penalty).append(".\n");
        return sb.toString();
    }

    private String scaleRowForDirect(int n) {
        if (n >= 5) return "5 и более прямых даёт 0/30.";
        if (n >= 3) return n + " прямых даёт 3/30.";
        if (n == 2) return "2 прямых даёт 6/30.";
        return "1 прямой даёт 12/30.";
    }

    private String scaleRowForIndirect(int n) {
        if (n >= 6) return "6 и более косвенных при отсутствии прямых даёт 12/30.";
        if (n >= 3) return n + " косвенных при отсутствии прямых даёт 18/30.";
        return n + " косвенных при отсутствии прямых даёт 24/30.";
    }

    private String joinNames(List<String> names, int cap) {
        if (names.size() <= cap) return names.stream().collect(Collectors.joining(", "));
        String head = names.subList(0, cap).stream().collect(Collectors.joining(", "));
        return head + " и ещё " + (names.size() - cap);
    }

    // =========================================================================
    //  HTTP
    // =========================================================================

    private String buildRequestBody(String userPrompt) {
        try {
            ObjectNode root = objectMapper.createObjectNode();
            root.put("model", MODEL);
            root.put("temperature", 0);
            root.put("max_tokens", MAX_TOKENS);

            ArrayNode messages = root.putArray("messages");
            messages.addObject().put("role", "user").put("content", userPrompt);

            return objectMapper.writeValueAsString(root);
        } catch (Exception e) {
            throw new RuntimeException("Ошибка сборки запроса к OpenRouter", e);
        }
    }

    // =========================================================================
    //  УТИЛИТЫ
    // =========================================================================

    private String translateRepair(RepairState state) {
        if (state == null) return "не указано";
        return switch (state) {
            case PRE_FINISHING  -> "под чистовую";
            case TYPICAL        -> "типовой";
            case DESIGNER       -> "дизайнерский";
            case SHELL_AND_CORE -> "требует ремонта";
        };
    }

    private boolean inRange(BigDecimal v, BigDecimal min, BigDecimal max) {
        if (min != null && v.compareTo(min) < 0) return false;
        if (max != null && v.compareTo(max) > 0) return false;
        return true;
    }

    private String formatRange(BigDecimal min, BigDecimal max, String unit) {
        if (min != null && max != null) return min + "–" + max + " " + unit;
        if (min != null) return "от " + min + " " + unit;
        if (max != null) return "до " + max + " " + unit;
        return "—";
    }

    private List<String> nvlList(List<String> list) {
        return list != null ? list : List.of();
    }

    private String nvl(Object value) {
        return value != null ? value.toString() : "не указано";
    }

    private ScoreExplainResponse fallback() {
        return new ScoreExplainResponse("AI-анализ временно недоступен. Оценку можно интерпретировать по шкале баллов самостоятельно.");
    }
}
