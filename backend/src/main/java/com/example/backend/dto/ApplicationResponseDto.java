package com.example.backend.dto;

import com.example.backend.entity.ApplicationStatus;
import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@Builder
public class ApplicationResponseDto {
    private Long id;
    private ApplicationStatus status;
    private String coverLetter;
    private LocalDateTime createdAt;
    private String rejectionReason; // <-- ДОБАВИЛИ

    // Вложенные объекты с самым необходимым минимумом информации
    private PropertyShortInfo property;
    private TenantShortInfo tenant;

    @Data
    @Builder
    public static class PropertyShortInfo {
        private Long id;
        private String title;
        private String address;
    }

    @Data
    @Builder
    public static class TenantShortInfo {
        private Long id;
        private String email;
        private String name;
        private String phone;
    }
}