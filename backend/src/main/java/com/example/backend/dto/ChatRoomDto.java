package com.example.backend.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class ChatRoomDto {
    private Long id;
    private Long applicationId;
    private Long landlordId;
    private String landlordName;
    private Long tenantId;
    private String tenantName;
}
