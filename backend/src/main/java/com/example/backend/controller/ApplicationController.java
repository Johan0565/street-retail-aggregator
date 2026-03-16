package com.example.backend.controller;
import com.example.backend.dto.CreateApplicationRequest;
import com.example.backend.dto.UpdateApplicationStatusRequest;
import com.example.backend.entity.Application;
import com.example.backend.service.ApplicationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
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
    public ResponseEntity<Application> createApplication(
            @RequestBody CreateApplicationRequest request,
            Principal principal) {

        Long tenantId = extractUserIdFromPrincipal(principal);
        Application application = applicationService.createApplication(
                tenantId,
                request.getPropertyId(),
                request.getCoverLetter()
        );
        return ResponseEntity.status(HttpStatus.CREATED).body(application);
    }

    @GetMapping("/my-requests")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<Application>> getTenantApplications(Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(applicationService.getTenantApplications(tenantId));
    }

    @GetMapping("/incoming")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<List<Application>> getLandlordApplications(Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(applicationService.getLandlordApplications(landlordId));
    }

    @PatchMapping("/{applicationId}/status")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<Application> updateApplicationStatus(
            @PathVariable Long applicationId,
            @RequestBody UpdateApplicationStatusRequest request,
            Principal principal) {

        Long landlordId = extractUserIdFromPrincipal(principal);
        Application updatedApplication = applicationService.updateApplicationStatus(
                landlordId,
                applicationId,
                request.getStatus()
        );
        return ResponseEntity.ok(updatedApplication);
    }

    private Long extractUserIdFromPrincipal(Principal principal) {
        return 1L;
    }
}