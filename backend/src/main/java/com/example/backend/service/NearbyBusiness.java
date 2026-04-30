package com.example.backend.service;

import java.util.List;

/**
 * Заведение из 2GIS: имя + список рубрик (уже в нижнем регистре).
 */
public record NearbyBusiness(String name, List<String> rubrics) {}
