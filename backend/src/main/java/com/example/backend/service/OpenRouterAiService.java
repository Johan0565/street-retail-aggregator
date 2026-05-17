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
                - Объём: 4–8 предложений, сплошным текстом, без списков, без заголовков, без эмодзи.
                - Запрещено: вводные слова («Конечно», «Отлично», «Рассмотрим»), фразы вида «требует улучшений», «небольшая преимущественность», «относительная позиция», обобщённые оценки без цифр.
                - Запрещено объяснять алгоритм («баллы делятся так-то», «50 это максимум»). Только конкретные цифры из ФАКТОВ.
                - Конкурентов УПОМИНАЙ ПОИМЁННО строго по правилу:
                    • если прямых ≤ 5 — назови КАЖДОГО;
                    • если прямых 6–15 — назови первые 5 из списка и допиши «и ещё N»;
                    • если прямых ≥ 16 — назови первые 3 наиболее узнаваемых и допиши «и ещё N»;
                    • то же для косвенных, но: ≤ 3 — все, 4–10 — первые 3 + «и ещё N», 11+ — первые 2 + «и ещё N».
                - Если в ФАКТАХ перечислены имена конкурентов — обязательно вставь хотя бы те, что положено по правилу выше. Не выдумывай и не сокращай до родовых слов («несколько аптек»): только конкретные имена из списка.
                - Если в ФАКТАХ указано «безымянных N» — добавь это число к фразе про конкурентов (например, «… и ещё 4 без названия»).
                - Последнее предложение: «Итог: N/100, главное ограничение — …» или «Итог: N/100, ограничений по данным алгоритма нет».

                ПРИМЕР ХОРОШЕГО ОТВЕТА (на других данных, много конкурентов):
                Помещение на Арбате площадью 65 м² за 320 000 ₽/мес попадает в бюджет и площадь полностью. По технике штрафов нет. В радиусе 1 км найдено 22 прямых конкурента — «36,6», «Ригла», «Самсон-фарма», «Горздрав», «Неофарм» и ещё 17, плюс 4 без названия, что по шкале даёт 0/30. По синергии желаемые соседи не заданы, балл по умолчанию 20/15. Итог: 50/100, главное ограничение — высокая плотность прямых конкурентов.

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

        sb.append("\nФИНАНСЫ ").append(scored.getFinancialScore()).append("/20:\n");
        sb.append(buildFinancialBreakdown(p, profile));

        sb.append("\nТЕХНИКА ").append(scored.getTechnicalScore()).append("/20:\n");
        sb.append(buildTechnicalBreakdown(p, profile));

        sb.append("\nКОНКУРЕНТЫ ").append(scored.getCompetitorScore()).append("/40:\n");
        sb.append(buildCompetitorBreakdown(scored));

        sb.append("\nСИНЕРГИЯ С СОСЕДЯМИ ").append(scored.getSynergyScore()).append("/15:\n");
        sb.append(buildSynergyBreakdown(scored, profile));

        sb.append("\nТРАНСПОРТ ").append(scored.getTransportScore()).append("/5:\n");
        sb.append(buildTransportBreakdown(scored));

        sb.append("\nИТОГ: ").append(scored.getTotalScore()).append("/100 (")
          .append(nvl(scored.getMatchLabel())).append(").");
        return sb.toString();
    }

    private String buildTransportBreakdown(ScoredPropertyDto scored) {
        var breakdown = scored.getBreakdown();
        if (breakdown == null || breakdown.getTransport() == null) {
            return "- данные о транспорте недоступны.\n";
        }
        var t = breakdown.getTransport();
        if ("NONE".equals(t.getNearestType()) || t.getNearestDistanceMeters() < 0) {
            return "- " + nvl(t.getReason()) + "; балл 0/5.\n";
        }
        return "- " + nvl(t.getReason()) + ". Из 5 баллов 5 отведены ТОЛЬКО на доступ к транспорту, "
                + "поэтому общая оценка не может быть выше 95 без близкой остановки.\n";
    }

    private String buildSynergyBreakdown(ScoredPropertyDto scored, SearchProfile profile) {
        List<String> neighbors = nvlList(scored.getSynergyNeighborNames());
        int desired = (profile == null || profile.getDesiredNeighbors() == null)
                ? 0 : profile.getDesiredNeighbors().size();

        if (desired == 0) {
            return "- арендатор не указывал желаемых соседей; синергический балл максимальный по умолчанию.\n";
        }
        if (neighbors.isEmpty()) {
            return "- желаемых соседей рядом не найдено ни одного из " + desired + " категорий; балл 0/15.\n";
        }
        return "- найдены желаемые соседи (" + neighbors.size() + "): "
                + joinNames(neighbors, 7) + ". Балл " + scored.getSynergyScore() + "/15.\n";
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
            if (maxB != null && price.compareTo(maxB) > 0) {
                sb.append("- цена ").append(price).append(" ₽/мес выше бюджета (макс. ").append(maxB).append(" ₽).\n");
            } else if (minB != null && price.compareTo(minB) < 0) {
                sb.append("- цена ").append(price).append(" ₽/мес ниже нижней границы бюджета (")
                  .append(minB).append(" ₽) — это плюс, штрафа нет.\n");
            } else {
                sb.append("- цена ").append(price).append(" ₽/мес укладывается в бюджет ").append(range).append(".\n");
            }
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

        // Мощность — градиент: штраф пропорционален дефициту, null = половина.
        Integer requiredPowerBoxed = profile.getMinPowerKw();
        if (requiredPowerBoxed != null && requiredPowerBoxed.intValue() > 0) {
            int req = requiredPowerBoxed.intValue();
            Integer actualBoxed = p.getPowerKw();
            if (actualBoxed == null) {
                penalties.add("- мощность не указана арендодателем (требовалось от " + req + " кВт), −1.5 (половина).");
            } else {
                int actual = actualBoxed.intValue();
                if (actual < req) {
                    double deficit = 1.0 - ((double) actual / req);
                    double cost = 3.0 * Math.min(1.0, Math.max(0.0, deficit));
                    penalties.add(String.format("- мощности %d кВт не хватает (требовалось от %d кВт, дефицит %.0f%%), −%.1f.",
                            actual, req, deficit * 100, cost));
                }
            }
        }
        // Потолки — градиент: каждые недостающие 30 см = полный штраф.
        if (profile.getMinCeilingHeight() != null) {
            BigDecimal req = profile.getMinCeilingHeight();
            BigDecimal actual = p.getCeilingHeight();
            if (actual == null) {
                penalties.add("- высота потолков не указана арендодателем (требовалось от " + req + " м), −1 (половина).");
            } else if (actual.compareTo(req) < 0) {
                double deficitM = req.subtract(actual).doubleValue();
                double cost = 2.0 * Math.min(1.0, deficitM / 0.30);
                penalties.add(String.format("- потолки %s м ниже требуемых %s м (дефицит %.2f м), −%.1f.",
                        actual, req, deficitM, cost));
            }
        }

        if (penalties.isEmpty())
            return "- помещение полностью отвечает техническим требованиям арендатора.\n";
        return String.join("\n", penalties) + "\n";
    }

    /**
     * Бинарный штраф: «нет» → полный, «не указано» → половина (uncertainty discount).
     */
    private void addPenalty(List<String> out, Boolean required, Boolean has, String name, int cost) {
        if (!Boolean.TRUE.equals(required)) return;
        if (Boolean.TRUE.equals(has)) return;
        if (has == null) {
            out.add("- арендатор требовал " + name + ", в помещении не указано, −" + (cost / 2.0) + " (половина).");
        } else {
            out.add("- арендатор требовал " + name + ", в помещении нет, −" + cost + ".");
        }
    }

    private String buildCompetitorBreakdown(ScoredPropertyDto scored) {
        List<String> direct   = nvlList(scored.getDirectCompetitorNames());
        List<String> indirect = nvlList(scored.getIndirectCompetitorNames());
        int score = scored.getCompetitorScore();
        int penalty = 40 - score;

        StringBuilder sb = new StringBuilder();

        if (direct.isEmpty() && indirect.isEmpty()) {
            sb.append("- в радиусе поиска не найдено ни прямых, ни косвенных конкурентов; балл максимальный, 40/40.\n");
            return sb.toString();
        }

        // Имена в списках уже отсортированы по близости (ближайший первым) —
        // об этом важно сказать AI, чтобы он не врал «5 конкурентов = провал».
        if (!direct.isEmpty()) {
            sb.append(formatCompetitorLine("прямые конкуренты (по близости)", direct, 20)).append('\n');
        } else {
            sb.append("- прямых конкурентов нет.\n");
        }

        if (!indirect.isEmpty()) {
            sb.append(formatCompetitorLine("косвенные конкуренты (по близости)", indirect, 15)).append('\n');
        }

        sb.append("- логика балла: distance-weighted exp-decay. Близкий конкурент весит ~1, ")
          .append("дальний в радиусе 1 км — ~0.05. Score = 40 · exp(-1.0·Σw_прямых − 0.3·Σw_косвенных). ")
          .append("Само количество конкурентов меньше важно, чем их близость к адресу.\n");
        sb.append("- итог по конкурентам: ").append(score).append("/40, потеряно ").append(penalty).append(".\n");
        return sb.toString();
    }

    /**
     * Готовит строку конкурентов для AI:
     *  - отделяет «безымянные» POI (имя вида "amenity=pharmacy" — OSM-объект без тега name);
     *  - в перечисление передаёт только реальные имена, но не больше {@code nameCap};
     *  - оставляет общий счёт (named+unnamed), а число безымянных указывает отдельно,
     *    чтобы AI мог написать «…и ещё 4 без названия» по правилам промпта.
     */
    private String formatCompetitorLine(String label, List<String> names, int nameCap) {
        List<String> named = new ArrayList<>(names.size());
        int unnamed = 0;
        for (String n : names) {
            if (isUnnamedPlaceholder(n)) unnamed++;
            else named.add(n);
        }
        StringBuilder line = new StringBuilder();
        line.append("- ").append(label).append(" (").append(names.size()).append(" всего");
        if (unnamed > 0) line.append(", безымянных ").append(unnamed);
        line.append("): ");
        if (named.isEmpty()) {
            line.append("все без названия в OSM");
        } else {
            line.append(joinNames(named, nameCap));
        }
        line.append('.');
        return line.toString();
    }

    /** Имя «amenity=pharmacy», «shop=clothes» — это OSM-заглушка для POI без name. */
    private boolean isUnnamedPlaceholder(String name) {
        if (name == null || name.isEmpty()) return true;
        return name.matches("^(shop|amenity|office|healthcare|leisure|craft|tourism)=.+");
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
