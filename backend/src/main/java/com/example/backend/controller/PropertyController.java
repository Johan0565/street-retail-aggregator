package com.example.backend.controller;

import com.example.backend.dto.CreatePropertyRequest;
import com.example.backend.dto.ScoreExplainResponse;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.Property;
import com.example.backend.entity.User;
import com.example.backend.service.OpenRouterAiService;
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
    private final OpenRouterAiService openRouterAiService;

    @GetMapping("/{id}")
    public ResponseEntity<Property> getPropertyById(@PathVariable Long id) {
        return ResponseEntity.ok(propertyService.getPropertyById(id));
    }

    /**
     * Возвращает детальный скоринг помещения с реальными данными о конкурентах
     * из 2GIS для активного проекта поиска арендатора.
     * 204 No Content — если у арендатора нет активного проекта поиска.
     */
    @GetMapping("/{id}/score")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<ScoredPropertyDto> getPropertyScore(
            @PathVariable Long id, Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        ScoredPropertyDto score = propertyService.scorePropertyForTenant(tenantId, id);
        if (score == null) {
            return ResponseEntity.noContent().build();
        }
        return ResponseEntity.ok(score);
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
    /**
     * GET /api/properties/{id}/score-explain
     * Генерирует текстовое объяснение оценки помещения через LLM (OpenRouter).
     * 204 — если у арендатора нет активного профиля поиска.
     */
    @GetMapping("/{id}/score-explain")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<ScoreExplainResponse> explainPropertyScore(
            @PathVariable Long id,
            Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        ScoredPropertyDto scored = propertyService.scorePropertyForTenant(tenantId, id);
        if (scored == null) {
            return ResponseEntity.noContent().build();
        }
        return ResponseEntity.ok(openRouterAiService.explainScore(scored));
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
    @PostMapping("/{propertyId}/favorite")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<Void> addFavorite(@PathVariable Long propertyId, Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        propertyService.addFavorite(tenantId, propertyId);
        return ResponseEntity.ok().build();
    }

    @DeleteMapping("/{propertyId}/favorite")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<Void> removeFavorite(@PathVariable Long propertyId, Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        propertyService.removeFavorite(tenantId, propertyId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/favorites")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<Property>> getMyFavorites(Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(propertyService.getFavorites(tenantId));
    }

    @GetMapping
    public ResponseEntity<List<Property>> getAllProperties() {
        return ResponseEntity.ok(propertyService.getAllPublishedProperties());
    }
}