package com.example.backend.config;

import com.example.backend.entity.BusinessCategory;
import com.example.backend.repository.BusinessCategoryRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Создаёт иерархию категорий бизнеса при старте приложения (идемпотентно).
 * Каждой категории присваивается список OSM-тегов в формате "key=value"
 * (CSV), по которым она будет сматчена с результатами Overpass API.
 *
 * Источник тегов — OpenStreetMap Wiki (https://wiki.openstreetmap.org/wiki/Map_features).
 * В России теги ставятся аккуратно: pharmacy/cafe/restaurant/clothes/etc.
 * почти всегда совпадают с типом заведения.
 */
@Component
@RequiredArgsConstructor
@Slf4j
@Order(1)
public class DataInitializer implements CommandLineRunner {

    private final BusinessCategoryRepository categoryRepository;

    @Override
    @Transactional
    public void run(String... args) {
        initCategories();
    }

    private void initCategories() {
        // ── Еда и напитки ────────────────────────────────────────────────────
        BusinessCategory food = findOrCreate("Еда и напитки", null, null);

        findOrCreate("Продуктовый магазин", food,
                "shop=supermarket,shop=convenience,shop=grocery,shop=greengrocer,shop=general");
        findOrCreate("Кофейня", food,
                "amenity=cafe,shop=coffee");
        findOrCreate("Ресторан", food,
                "amenity=restaurant");
        findOrCreate("Кафе", food,
                "amenity=cafe,amenity=food_court,amenity=ice_cream");
        findOrCreate("Пекарня", food,
                "shop=bakery,shop=pastry");
        findOrCreate("Кондитерская", food,
                "shop=confectionery,shop=chocolate,shop=pastry");
        findOrCreate("Фастфуд", food,
                "amenity=fast_food");
        findOrCreate("Бар", food,
                "amenity=bar,amenity=pub,amenity=nightclub,amenity=biergarten");

        // ── Красота и здоровье ───────────────────────────────────────────────
        BusinessCategory beauty = findOrCreate("Красота и здоровье", null, null);

        findOrCreate("Аптека", beauty,
                "amenity=pharmacy,healthcare=pharmacy,shop=chemist");
        findOrCreate("Парикмахерская", beauty,
                "shop=hairdresser,craft=hairdresser,shop=hairdresser_supply");
        findOrCreate("Салон красоты", beauty,
                "shop=beauty,shop=cosmetics,shop=perfumery");
        findOrCreate("Маникюр и педикюр", beauty,
                "shop=nails,shop=beauty");
        findOrCreate("Косметология", beauty,
                "shop=beauty,shop=cosmetics,shop=massage,healthcare=cosmetic_surgery");
        findOrCreate("Медицинский центр", beauty,
                "amenity=clinic,amenity=doctors,amenity=dentist,healthcare=clinic," +
                "healthcare=doctor,healthcare=centre,healthcare=hospital,healthcare=dentist");
        findOrCreate("Оптика", beauty,
                "shop=optician,healthcare=optometrist");

        // ── Товары ───────────────────────────────────────────────────────────
        BusinessCategory goods = findOrCreate("Товары", null, null);

        findOrCreate("Одежда", goods,
                "shop=clothes,shop=boutique,shop=fashion,shop=fashion_accessories");
        findOrCreate("Обувь", goods,
                "shop=shoes,shop=boots");
        findOrCreate("Ювелирный магазин", goods,
                "shop=jewelry,shop=jewellery,shop=watches");
        findOrCreate("Цветочный магазин", goods,
                "shop=florist,shop=garden_centre");
        findOrCreate("Зоомагазин", goods,
                "shop=pet,shop=pet_grooming,amenity=veterinary");
        findOrCreate("Спорттовары", goods,
                "shop=sports,shop=outdoor,shop=bicycle,shop=hunting,shop=fishing,shop=ski");
        findOrCreate("Детские товары", goods,
                "shop=baby_goods,shop=toys,shop=kids,shop=children");

        // ── Сервис и услуги ──────────────────────────────────────────────────
        BusinessCategory service = findOrCreate("Сервис и услуги", null, null);

        findOrCreate("ПВЗ", service,
                "shop=parcel_locker,amenity=parcel_locker,amenity=post_office," +
                "office=courier,amenity=post_depot");
        findOrCreate("Банк", service,
                "amenity=bank,office=financial,office=insurance");
        findOrCreate("Химчистка", service,
                "shop=dry_cleaning,shop=laundry,shop=tailor,craft=tailor,craft=dressmaker");
        findOrCreate("Ремонт электроники", service,
                "shop=mobile_phone,shop=electronics,craft=electronics_repair,craft=phone_repair");
        findOrCreate("Туристическое агентство", service,
                "office=travel_agent,shop=travel_agency,tourism=information");

        // ── Образование и развитие ───────────────────────────────────────────
        BusinessCategory edu = findOrCreate("Образование и развитие", null, null);

        findOrCreate("Детский центр", edu,
                "amenity=kindergarten,amenity=childcare,leisure=playground");
        findOrCreate("Учебный центр", edu,
                "amenity=school,amenity=college,amenity=university,amenity=language_school," +
                "amenity=driving_school,amenity=training,office=educational_institution");
        findOrCreate("Фитнес-клуб", edu,
                "leisure=fitness_centre,leisure=sports_centre,leisure=dance,sport=fitness");

        log.info("Категории бизнеса инициализированы (OSM-теги Overpass).");
    }

    private BusinessCategory findOrCreate(String name, BusinessCategory parent, String osmTags) {
        BusinessCategory category = categoryRepository.findByName(name).orElseGet(() -> {
            BusinessCategory newCat = BusinessCategory.builder()
                    .name(name)
                    .parentCategory(parent)
                    .build();
            return categoryRepository.save(newCat);
        });

        boolean changed = false;
        if (osmTags != null && !osmTags.equals(category.getOsmTags())) {
            category.setOsmTags(osmTags);
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
}
