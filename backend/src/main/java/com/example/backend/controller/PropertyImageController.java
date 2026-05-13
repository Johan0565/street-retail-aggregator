package com.example.backend.controller;

import com.example.backend.entity.PropertyImage;
import com.example.backend.entity.User;
import com.example.backend.service.PropertyImageService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.security.Principal;
import java.util.List;

@RestController
@RequestMapping("/api/properties/{propertyId}/images")
@RequiredArgsConstructor
public class PropertyImageController {

    private final PropertyImageService propertyImageService;

    @PostMapping(consumes = "multipart/form-data")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<List<PropertyImage>> upload(
            @PathVariable Long propertyId,
            @RequestPart("files") List<MultipartFile> files,
            Principal principal) {
        Long landlordId = userId(principal);
        return ResponseEntity.ok(propertyImageService.upload(landlordId, propertyId, files));
    }

    @DeleteMapping("/{imageId}")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<Void> delete(
            @PathVariable Long propertyId,
            @PathVariable Long imageId,
            Principal principal) {
        propertyImageService.delete(userId(principal), propertyId, imageId);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{imageId}/main")
    @PreAuthorize("hasRole('LANDLORD')")
    public ResponseEntity<Void> setMain(
            @PathVariable Long propertyId,
            @PathVariable Long imageId,
            Principal principal) {
        propertyImageService.setMain(userId(principal), propertyId, imageId);
        return ResponseEntity.noContent().build();
    }

    private Long userId(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            return ((User) authToken.getPrincipal()).getId();
        }
        throw new RuntimeException("Не удалось извлечь ID пользователя из токена");
    }
}
