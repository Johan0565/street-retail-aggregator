package com.example.backend.dto;

import lombok.Data;
import java.util.List;

@Data
public class BusinessCategoryDto {
    private Long id;
    private String name;
    private List<BusinessCategoryDto> subCategories; // Вложенные подкатегории
}