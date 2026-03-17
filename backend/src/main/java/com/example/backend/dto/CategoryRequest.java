package com.example.backend.dto;
import lombok.Data;

@Data
public class CategoryRequest {
    private String name;
    private Long parentId; // Может быть null, если это главная категория
}