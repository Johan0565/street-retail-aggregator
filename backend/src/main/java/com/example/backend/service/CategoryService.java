package com.example.backend.service;

import com.example.backend.dto.BusinessCategoryDto;
import com.example.backend.dto.CategoryRequest;
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
    @Transactional(readOnly = true)
    public BusinessCategoryDto getCategoryById(Long id) {
        BusinessCategory category = categoryRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Категория не найдена"));
        return mapToDto(category);
    }

    @Transactional
    public BusinessCategoryDto createCategory(CategoryRequest request) {
        BusinessCategory category = new BusinessCategory();
        category.setName(request.getName());

        if (request.getParentId() != null) {
            BusinessCategory parent = categoryRepository.findById(request.getParentId())
                    .orElseThrow(() -> new RuntimeException("Родительская категория не найдена"));
            category.setParentCategory(parent);
        }
        return mapToDto(categoryRepository.save(category));
    }

    @Transactional
    public BusinessCategoryDto updateCategory(Long id, CategoryRequest request) {
        BusinessCategory category = categoryRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Категория не найдена"));

        category.setName(request.getName());

        if (request.getParentId() != null) {
            BusinessCategory parent = categoryRepository.findById(request.getParentId())
                    .orElseThrow(() -> new RuntimeException("Родительская категория не найдена"));
            category.setParentCategory(parent);
        } else {
            category.setParentCategory(null);
        }
        return mapToDto(categoryRepository.save(category));
    }

    @Transactional
    public void deleteCategory(Long id) {
        if (!categoryRepository.existsById(id)) {
            throw new RuntimeException("Категория не найдена");
        }
        categoryRepository.deleteById(id);
    }
}