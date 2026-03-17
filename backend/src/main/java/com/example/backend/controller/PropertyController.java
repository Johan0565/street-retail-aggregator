package com.example.backend.controller;

import com.example.backend.dto.CreatePropertyRequest;
import com.example.backend.entity.Property;
import com.example.backend.entity.User;
import com.example.backend.service.PropertyService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
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
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Не удалось извлечь ID пользователя из токена");
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
    @GetMapping("/my")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<List<Property>> getMyProperties(Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(propertyService.getMyProperties(landlordId));
    }

    /**
     * Обновить объявление
     */
    @PutMapping("/{id}")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<Property> updateProperty(
            @PathVariable Long id,
            @RequestBody CreatePropertyRequest request,
            Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(propertyService.updateProperty(landlordId, id, request));
    }

    /**
     * Удалить (архивировать) объявление
     */
    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<Void> deleteProperty(@PathVariable Long id, Principal principal) {
        Long landlordId = extractUserIdFromPrincipal(principal);
        propertyService.deleteProperty(landlordId, id);
        return ResponseEntity.noContent().build();
    }
    // ... существующий код ...

    @GetMapping
    public ResponseEntity<List<Property>> getAllProperties() {
        return ResponseEntity.ok(propertyService.getAllPublishedProperties());
    }
}