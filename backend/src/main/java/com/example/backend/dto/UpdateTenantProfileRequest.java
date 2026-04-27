package com.example.backend.dto;

import lombok.Data;

@Data
public class UpdateTenantProfileRequest {
    private String name;
    private String inn;
    private String phone;
}
