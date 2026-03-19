package com.example.backend.controller;

import com.example.backend.entity.Property;
import com.example.backend.entity.User;
import com.example.backend.service.FavoriteService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;

@RestController
@RequestMapping("/api/favorites")
@RequiredArgsConstructor
public class FavoriteController {

    private final FavoriteService favoriteService;

    @GetMapping
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<Property>> getMyFavorites(Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(favoriteService.getFavorites(tenantId));
    }

    @PostMapping("/{propertyId}")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<Void> addFavorite(
            @PathVariable Long propertyId,
            Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        favoriteService.addFavorite(tenantId, propertyId);
        return ResponseEntity.ok().build();
    }

    @DeleteMapping("/{propertyId}")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<Void> removeFavorite(
            @PathVariable Long propertyId,
            Principal principal) {
        Long tenantId = extractUserIdFromPrincipal(principal);
        favoriteService.removeFavorite(tenantId, propertyId);
        return ResponseEntity.noContent().build();
    }

    // Вспомогательный метод (такой же, как в других контроллерах)
    private Long extractUserIdFromPrincipal(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Не удалось извлечь ID пользователя из токена");
    }
}