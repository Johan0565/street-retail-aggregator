package com.example.backend.config;

import com.example.backend.entity.BusinessCategory;
import com.example.backend.repository.BusinessCategoryRepository;
import com.example.backend.service.GisRubricCatalogService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Создаёт иерархию категорий бизнеса при старте приложения (идемпотентно).
 * Каждой категории присваивается список ключевых слов (twoGisKeywords)
 * для сопоставления с рубриками 2GIS Places API.
 */
@Component
@RequiredArgsConstructor
@Slf4j
@Order(1)
public class DataInitializer implements CommandLineRunner {

    private final BusinessCategoryRepository categoryRepository;
    private final GisRubricCatalogService gisRubricCatalogService;

    @Override
    @Transactional
    public void run(String... args) {
        initCategories();
    }

    private void initCategories() {
        // ── Еда и напитки ────────────────────────────────────────────────────
        BusinessCategory food = findOrCreate("Еда и напитки", null, null);

        findOrCreate("Продуктовый магазин", food,
                "продукты,супермаркет,гастроном,минимаркет,универсам,продуктовый магазин,магазин продуктов,продукты питания,бакалея,гипермаркет");
        findOrCreate("Кофейня", food,
                "кофейня,кофе,coffee shop,кофе-бар");
        findOrCreate("Ресторан", food,
                "ресторан,restaurant,трактир,лаундж,банкетный зал");
        findOrCreate("Кафе", food,
                "кафе,бистро,столовая,кафетерий,чайхана,хинкальная,блинная,пельменная,чебуречная,шашлычная,пышечная,кулинария,закусочная,антикафе,тайм-кафе,гастропаб,корнер,фуд-корт,пиццерия,суши-бар,общественное питание");
        findOrCreate("Пекарня", food,
                "пекарня,булочная,хлебобулочные изделия");
        findOrCreate("Кондитерская", food,
                "кондитерская,торты на заказ,сладости,десерты");
        findOrCreate("Фастфуд", food,
                "фастфуд,быстрое питание,бургер,пиццерия,суши,роллы,шаурма,стрит-фуд");
        findOrCreate("Бар", food,
                "бар,паб,пивной бар,коктейльный бар,ночной клуб,рюмочная,караоке,лаундж-бар");

        // ── Красота и здоровье ───────────────────────────────────────────────
        BusinessCategory beauty = findOrCreate("Красота и здоровье", null, null);

        findOrCreate("Аптека", beauty,
                "аптека,аптечный пункт,фармация,оптика,линзы,очки");
        findOrCreate("Парикмахерская", beauty,
                "парикмахерская,барбершоп,студия стрижки,мужская стрижка,детская стрижка");
        findOrCreate("Салон красоты", beauty,
                "салон красоты,beauty studio,студия красоты,маникюр,педикюр,nail,ногтевой сервис,nail studio,косметология,спа,spa,массаж,уход за кожей");
        findOrCreate("Маникюр и педикюр", beauty,
                "маникюр,педикюр,ногтевой сервис,nail studio,nail,покрытие ногтей");
        findOrCreate("Косметология", beauty,
                "косметология,спа,spa,массаж,уход за кожей,эпиляция,лазерная эпиляция,солярий");
        findOrCreate("Медицинский центр", beauty,
                "медицинский центр,клиника,медицина,врач,диагностика");
        findOrCreate("Оптика", beauty,
                "оптика,магазин очков,линзы,очки");

        // ── Товары ───────────────────────────────────────────────────────────
        BusinessCategory goods = findOrCreate("Товары", null, null);

        findOrCreate("Одежда", goods,
                "магазин одежды,одежда,бутик,шоурум,женская одежда,мужская одежда,детская одежда,мода,fashion");
        findOrCreate("Обувь", goods,
                "магазин обуви,обувной магазин,обувь,кроссовки,кожаная обувь");
        findOrCreate("Ювелирный магазин", goods,
                "ювелирный магазин,украшения,золото,бижутерия,ювелирные изделия");
        findOrCreate("Цветочный магазин", goods,
                "цветочный магазин,цветы,флористика,флорист");
        findOrCreate("Зоомагазин", goods,
                "зоомагазин,зоотовары,корм для животных,ветеринарные товары");
        findOrCreate("Спорттовары", goods,
                "спортивный магазин,спорттовары,спортивное питание");
        findOrCreate("Детские товары", goods,
                "детские товары,игрушки,детский магазин");

        // ── Сервис и услуги ──────────────────────────────────────────────────
        BusinessCategory service = findOrCreate("Сервис и услуги", null, null);

        findOrCreate("ПВЗ", service,
                "пункт выдачи,пвз,wildberries,ozon,сдэк,cdek,boxberry,яндекс маркет");
        findOrCreate("Банк", service,
                "банк,отделение банка,банковский офис");
        findOrCreate("Химчистка", service,
                "химчистка,прачечная,ремонт одежды");
        findOrCreate("Ремонт электроники", service,
                "ремонт телефонов,ремонт электроники,сервисный центр,ремонт смартфонов");
        findOrCreate("Туристическое агентство", service,
                "туристическое агентство,туризм,туры,путёвки");

        // ── Образование и развитие ───────────────────────────────────────────
        BusinessCategory edu = findOrCreate("Образование и развитие", null, null);

        findOrCreate("Детский центр", edu,
                "детский центр,развивающий центр,дошкольное образование");
        findOrCreate("Учебный центр", edu,
                "учебный центр,курсы,образование,репетитор,языковая школа");
        findOrCreate("Фитнес-клуб", edu,
                "фитнес-клуб,тренажерный зал,спортзал,gym,фитнес");

        log.info("Категории бизнеса инициализированы.");
    }

    /**
     * Находит категорию по имени или создаёт её. Всегда обновляет twoGisKeywords:
     * seed-слова используются как затравка для поиска по официальному каталогу
     * рубрик 2GIS. Финальный список keywords — канонические имена 2GIS-рубрик,
     * чьи названия содержат seed (если 2GIS недоступен — берём seed как есть).
     */
    private BusinessCategory findOrCreate(String name, BusinessCategory parent, String seedKeywords) {
        BusinessCategory category = categoryRepository.findByName(name).orElseGet(() -> {
            BusinessCategory newCat = BusinessCategory.builder()
                    .name(name)
                    .parentCategory(parent)
                    .build();
            return categoryRepository.save(newCat);
        });

        String finalKeywords = resolveKeywords(name, seedKeywords);

        boolean changed = false;
        if (finalKeywords != null && !finalKeywords.equals(category.getTwoGisKeywords())) {
            category.setTwoGisKeywords(finalKeywords);
            changed = true;
        }
        if (parent != null && category.getParentCategory() == null) {
            category.setParentCategory(parent);
            changed = true;
        }
        if (changed) {
            categoryRepository.save(category);
        }
        return category;
    }

    /**
     * Расширяет seed-keywords до полного списка канонических имён 2GIS-рубрик.
     * Имя категории тоже добавляется в seed, чтобы покрыть случаи когда сама
     * категория совпадает с рубрикой 2GIS (например, «Кафе» → рубрика «Кафе»).
     */
    private String resolveKeywords(String categoryName, String seedKeywords) {
        if (seedKeywords == null || seedKeywords.isBlank()) return seedKeywords;

        Set<String> seeds = new LinkedHashSet<>();
        seeds.add(categoryName.toLowerCase());
        Arrays.stream(seedKeywords.split(",")).map(String::trim).forEach(seeds::add);

        List<String> expanded = gisRubricCatalogService.expandKeywords(seeds);
        if (expanded.isEmpty()) {
            log.warn("[CATEGORY] '{}': 2GIS-каталог недоступен, оставляем seed: '{}'", categoryName, seedKeywords);
            return seedKeywords;
        }

        // Объединяем canonical 2GIS-имена + seeds (на случай рубрик, которых нет в 2GIS).
        Set<String> merged = new LinkedHashSet<>(expanded);
        for (String s : seedKeywords.split(",")) merged.add(s.trim().toLowerCase());

        String result = String.join(",", merged);
        log.info("[CATEGORY] '{}': seed={} → итог из 2GIS-каталога ({} keywords)",
                categoryName, seedKeywords.split(",").length, merged.size());
        return result;
    }
}
