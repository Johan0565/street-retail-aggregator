package com.example.backend.controller;

import com.example.backend.dto.UpdateLandlordProfileRequest;
import com.example.backend.dto.UpdateTenantProfileRequest;
import com.example.backend.entity.LandlordProfile;
import com.example.backend.entity.TenantProfile;
import com.example.backend.entity.User;
import com.example.backend.service.ProfileService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.security.Principal;
import java.util.Map;

@RestController
@RequestMapping("/api/profiles")
@RequiredArgsConstructor
public class ProfileController {

    private final ProfileService profileService;

    // --- ЭНДПОИНТЫ АРЕНДАТОРА ---

    @GetMapping("/tenant/me")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<TenantProfile> getMyTenantProfile(Principal principal) {
        Long userId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(profileService.getTenantProfile(userId));
    }

    @PutMapping("/tenant/me")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<TenantProfile> updateMyTenantProfile(
            @RequestBody UpdateTenantProfileRequest request,
            Principal principal) {
        Long userId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(profileService.updateTenantProfile(userId, request));
    }

    // --- ЭНДПОИНТЫ АРЕНДОДАТЕЛЯ ---

    @GetMapping("/landlord/me")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<LandlordProfile> getMyLandlordProfile(Principal principal) {
        Long userId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(profileService.getLandlordProfile(userId));
    }

    @PutMapping("/landlord/me")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<LandlordProfile> updateMyLandlordProfile(
            @RequestBody UpdateLandlordProfileRequest request,
            Principal principal) {
        Long userId = extractUserIdFromPrincipal(principal);
        return ResponseEntity.ok(profileService.updateLandlordProfile(userId, request));
    }

    // Вспомогательный метод для извлечения ID из токена
    private Long extractUserIdFromPrincipal(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Не удалось извлечь ID пользователя из токена");
    }
    // --- АВАТАРКА ---

    @PostMapping(value = "/me/avatar", consumes = "multipart/form-data")
    public ResponseEntity<Map<String, String>> uploadAvatar(
            @RequestPart("file") MultipartFile file,
            Principal principal) {
        Long userId = extractUserIdFromPrincipal(principal);
        String url = profileService.uploadAvatar(userId, file);
        return ResponseEntity.ok(Map.of("avatarUrl", url));
    }

    @DeleteMapping("/me/avatar")
    public ResponseEntity<Void> deleteAvatar(Principal principal) {
        Long userId = extractUserIdFromPrincipal(principal);
        profileService.deleteAvatar(userId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/tenant/{userId}")
    public ResponseEntity<TenantProfile> getTenantProfileById(@PathVariable Long userId) {
        return ResponseEntity.ok(profileService.getTenantProfile(userId));
    }

    /**
     * Публичный просмотр профиля арендодателя по ID пользователя
     */
    @GetMapping("/landlord/{userId}")
    public ResponseEntity<LandlordProfile> getLandlordProfileById(@PathVariable Long userId) {
        return ResponseEntity.ok(profileService.getLandlordProfile(userId));
    }
}