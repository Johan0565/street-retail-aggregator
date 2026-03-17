package com.example.backend.dto;

import lombok.Data;

@Data
public class UpdateLandlordProfileRequest {
    private String companyName;
    private String inn;
    private String phone;
}