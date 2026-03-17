package com.example.backend.controller;

import com.example.backend.dto.CreatePropertyRequest;
import com.example.backend.entity.Property;
import com.example.backend.service.PropertyService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;

@RestController
@RequestMapping("/api/properties")
@RequiredArgsConstructor
public class PropertyController {

    private final PropertyService propertyService;

    @GetMapping("/{id}")
    public ResponseEntity<Property> getPropertyById(@PathVariable Long id) {
        return ResponseEntity.ok(propertyService.getPropertyById(id));
    }

    @GetMapping("/recommended")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<Property>> getRecommendedProperties(Principal principal) {

        Long tenantId = extractUserIdFromPrincipal(principal);

        List<Property> recommended = propertyService.getRecommendedPropertiesForTenant(tenantId);
        return ResponseEntity.ok(recommended);
    }

    private Long extractUserIdFromPrincipal(Principal principal) {

        return 1L;
    }
    @PostMapping
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<Property> createProperty(
            @RequestBody CreatePropertyRequest request,
            Principal principal) {

        Long landlordId = extractUserIdFromPrincipal(principal);
        Property createdProperty = propertyService.createProperty(landlordId, request);

        return ResponseEntity.status(HttpStatus.CREATED).body(createdProperty);
    }
}