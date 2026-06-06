package com.example.backend.dto;

import com.example.backend.entity.enums.*;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class BuildingSpecsRequest {
    private String buildingName;
    private BuildingClass buildingClass;
    private Integer buildYear;
    private Integer totalFloors;
    private Integer powerKw;
    private Boolean hasWater;
    private Boolean hasVentilation;
    private Boolean hasSeparateEntrance;
    private RepairState repairState;
    private BigDecimal ceilingHeight;
    private LayoutType layout;
    private AccessType accessType;
    private HeatingType heatingType;
    private FurnitureState furnitureState;
}
