package com.example.backend.controller;

import com.example.backend.dto.BusinessCategoryDto;
import com.example.backend.service.CategoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

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
    @GetMapping("/{id}")
    public ResponseEntity<BusinessCategoryDto> getCategoryById(@PathVariable Long id) {
        return ResponseEntity.ok(categoryService.getCategoryById(id));
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<BusinessCategoryDto> createCategory(@RequestBody com.example.backend.dto.CategoryRequest request) {
        return ResponseEntity.ok(categoryService.createCategory(request));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<BusinessCategoryDto> updateCategory(
            @PathVariable Long id,
            @RequestBody com.example.backend.dto.CategoryRequest request) {
        return ResponseEntity.ok(categoryService.updateCategory(id, request));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<Void> deleteCategory(@PathVariable Long id) {
        categoryService.deleteCategory(id);
        return ResponseEntity.noContent().build();
    }
}