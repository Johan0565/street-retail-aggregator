package com.example.backend.dto;

import com.example.backend.entity.enums.ApplicationStatus;
import lombok.Data;

@Data
public class UpdateApplicationStatusRequest {
    private ApplicationStatus status;
    private String rejectionReason; // <-- ДОБАВИЛИ
}