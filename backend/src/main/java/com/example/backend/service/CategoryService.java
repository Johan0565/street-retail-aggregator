package com.example.backend.service;

import com.example.backend.dto.BusinessCategoryDto;
import com.example.backend.entity.BusinessCategory;
import com.example.backend.repository.BusinessCategoryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class CategoryService {

    private final BusinessCategoryRepository categoryRepository;

    /**
     * Получить дерево всех категорий (для красивых выпадающих списков)
     */
    @Transactional(readOnly = true)
    public List<BusinessCategoryDto> getCategoryTree() {
        // Достаем только корневые категории (Ритейл, Общепит, Услуги и т.д.)
        List<BusinessCategory> rootCategories = categoryRepository.findByParentCategoryIsNull();

        // Превращаем их в DTO
        return rootCategories.stream()
                .map(this::mapToDto)
                .collect(Collectors.toList());
    }

    /**
     * Получить плоский список всех категорий (иногда фронтенду так удобнее)
     */
    @Transactional(readOnly = true)
    public List<BusinessCategoryDto> getAllFlat() {
        return categoryRepository.findAll().stream()
                .map(category -> {
                    BusinessCategoryDto dto = new BusinessCategoryDto();
                    dto.setId(category.getId());
                    dto.setName(category.getName());
                    // В плоском списке вложенность не передаем
                    return dto;
                })
                .collect(Collectors.toList());
    }

    // Вспомогательный рекурсивный метод для маппинга Entity -> Dto
    private BusinessCategoryDto mapToDto(BusinessCategory category) {
        BusinessCategoryDto dto = new BusinessCategoryDto();
        dto.setId(category.getId());
        dto.setName(category.getName());

        // Если у категории есть дети, мапим и их тоже
        if (category.getSubCategories() != null && !category.getSubCategories().isEmpty()) {
            dto.setSubCategories(
                    category.getSubCategories().stream()
                            .map(this::mapToDto)
                            .collect(Collectors.toList())
            );
        }

        return dto;
    }
}