package com.example.backend.dto;

import lombok.Builder;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
@Builder
public class TransactionReportDto {
    private Long applicationId;
    private Long propertyId;
    private String propertyTitle;
    private String propertyAddress;
    private String tenantEmail;
    private String tenantName;
    private String landlordEmail;
    private String landlordCompanyName;
    private BigDecimal pricePerMonth;
    private LocalDateTime dealConfirmedAt;
}
