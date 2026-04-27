package com.example.backend.config;

import com.example.backend.entity.BusinessCategory;
import com.example.backend.repository.BusinessCategoryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.Optional;

@Component
@RequiredArgsConstructor
public class DataInitializer implements CommandLineRunner {

    private final BusinessCategoryRepository categoryRepository;

    @Override
    public void run(String... args) {
        // Добавляем основные категории, если их нет
        createCategoryIfAbsent("Кофейня / Пекарня", "amenity=cafe");
        createCategoryIfAbsent("Ресторан", "amenity=restaurant");
        createCategoryIfAbsent("Продуктовый магазин", "shop=supermarket");
        createCategoryIfAbsent("Салон красоты", "shop=beauty");
        createCategoryIfAbsent("Аптека", "amenity=pharmacy");
        createCategoryIfAbsent("Магазин одежды", "shop=clothes");
        createCategoryIfAbsent("Банк", "amenity=bank");
        createCategoryIfAbsent("Спорт и фитнес", "leisure=fitness_centre");
    }

    private void createCategoryIfAbsent(String name, String osmTag) {
        Optional<BusinessCategory> existing = categoryRepository.findByName(name);
        if (existing.isEmpty()) {
            BusinessCategory category = BusinessCategory.builder()
                    .name(name)
                    .osmTag(osmTag)
                    .build();
            categoryRepository.save(category);
        } else {
            // Обновляем тег, если категория уже есть, но тега нет
            BusinessCategory category = existing.get();
            if (category.getOsmTag() == null || !category.getOsmTag().equals(osmTag)) {
                category.setOsmTag(osmTag);
                categoryRepository.save(category);
            }
        }
    }
}
