package com.example.backend.controller;

import com.example.backend.dto.BusinessCategoryDto;
import com.example.backend.service.CategoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/categories")
@RequiredArgsConstructor
public class CategoryController {

    private final CategoryService categoryService;

    /**
     * Получить иерархию категорий (дерево)
     * Открыто для всех.
     */
    @GetMapping
    public ResponseEntity<List<BusinessCategoryDto>> getCategoryTree() {
        return ResponseEntity.ok(categoryService.getCategoryTree());
    }

    /**
     * Получить все категории плоским списком
     * Открыто для всех.
     */
    @GetMapping("/flat")
    public ResponseEntity<List<BusinessCategoryDto>> getAllCategoriesFlat() {
        return ResponseEntity.ok(categoryService.getAllFlat());
    }
}