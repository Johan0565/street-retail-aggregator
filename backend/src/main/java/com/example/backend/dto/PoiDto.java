package com.example.backend.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class PoiDto {
    private String name;
    private String category;
    private double distanceMeters;
    private boolean isCompetitor;
}
