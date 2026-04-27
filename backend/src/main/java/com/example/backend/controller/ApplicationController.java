package com.example.backend.controller;

import com.example.backend.dto.ApplicationResponseDto;
import com.example.backend.dto.CreateApplicationRequest;
import com.example.backend.dto.UpdateApplicationStatusRequest;
import com.example.backend.entity.User;
import com.example.backend.service.ApplicationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;

@RestController
@RequestMapping("/api/applications")
@RequiredArgsConstructor
public class ApplicationController {

    private final ApplicationService applicationService;

    @PostMapping
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<ApplicationResponseDto> createApplication(
            @RequestBody CreateApplicationRequest request,
            Principal principal) {

        Long tenantId = extractUserIdFromPrincipal(principal);
        ApplicationResponseDto application = applicationService.createApplication(
                tenantId,
                request.getPropertyId(),
                request.getCoverLetter()
        );
        return ResponseEntity.status(HttpStatus.CREATED).body(application);
    }


    @GetMapping("/my-requests")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<ApplicationResponseDto>> getTenantApplications(Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(applicationService.getTenantApplications(tenantId));
    }

    @GetMapping("/incoming")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<List<ApplicationResponseDto>> getLandlordApplications(Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(applicationService.getLandlordApplications(landlordId));
    }

    @PatchMapping("/{applicationId}/status")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<ApplicationResponseDto> updateApplicationStatus(
            @PathVariable Long applicationId,
            @RequestBody UpdateApplicationStatusRequest request,
            Principal principal) {

        Long landlordId = extractUserIdFromPrincipal(principal);
        ApplicationResponseDto updatedApplication = applicationService.updateApplicationStatus(
                landlordId,
                applicationId,
                request.getStatus(),
                request.getRejectionReason()
        );
        return ResponseEntity.ok(updatedApplication);
    }

    private Long extractUserIdFromPrincipal(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Не удалось извлечь ID пользователя из токена");
    }

    /**
     * Отозвать (удалить) заявку
     * Защищено: только Арендатор.
     */
    @DeleteMapping("/{applicationId}")
    @PreAuthorize("hasAnyRole('TENANT', 'LANDLORD')")
    public ResponseEntity<Void> deleteApplication(
            @PathVariable Long applicationId,
            Principal principal) {
        Long currentUserId = extractUserIdFromPrincipal(principal);
        applicationService.deleteApplication(currentUserId, applicationId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{applicationId}")
    @PreAuthorize("hasAnyRole('TENANT', 'LANDLORD')")
    public ResponseEntity<ApplicationResponseDto> getApplicationById(
            @PathVariable Long applicationId,
            Principal principal) {
        User user = (User) ((UsernamePasswordAuthenticationToken) principal).getPrincipal();
        return ResponseEntity.ok(applicationService.getApplicationById(applicationId, user.getId(), user.getRole()));
    }
}