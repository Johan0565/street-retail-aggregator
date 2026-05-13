package com.example.backend.controller;

import com.example.backend.dto.AnalyticsDto;
import com.example.backend.entity.User;
import com.example.backend.service.AnalyticsService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;

@RestController
@RequestMapping("/api/analytics")
@RequiredArgsConstructor
public class AnalyticsController {

    private final AnalyticsService analyticsService;

    @GetMapping("/my-properties")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<AnalyticsDto> getMyAnalytics(Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(analyticsService.getLandlordAnalytics(landlordId));
    }

    @GetMapping("/property/{propertyId}")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<AnalyticsDto> getPropertyAnalytics(
            @PathVariable Long propertyId,
            Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        if (!analyticsService.isOwner(propertyId, landlordId)) {
            return ResponseEntity.status(403).build();
        }
        return ResponseEntity.ok(analyticsService.getPropertyAnalytics(propertyId));
    }

    @PostMapping("/view/{propertyId}")
    public ResponseEntity<Void> logView(@PathVariable Long propertyId, Principal principal) {
        Long viewerId = null;
        if (principal != null) {
            try {
                viewerId = extractUserIdFromPrincipal(principal);
            } catch (Exception ignored) {}
        }
        analyticsService.logPropertyView(propertyId, viewerId);
        return ResponseEntity.ok().build();
    }

    private Long extractUserIdFromPrincipal(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Unauthorized");
    }
}
