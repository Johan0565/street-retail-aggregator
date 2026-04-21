package com.example.backend.controller;

import com.example.backend.dto.CreateSearchProfileRequest;
import com.example.backend.dto.ScoredPropertyDto;
import com.example.backend.entity.SearchProfile;
import com.example.backend.entity.User;
import com.example.backend.service.SearchProfileService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;

@RestController
@RequestMapping("/api/search-profiles")
@RequiredArgsConstructor
public class SearchProfileController {

    private final SearchProfileService searchProfileService;

    /**
     * POST /api/search-profiles
     * Создать новый проект поиска.
     */
    @PostMapping
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<SearchProfile> createSearchProfile(
            @RequestBody CreateSearchProfileRequest request,
            Principal principal) {

        Long tenantId = extractUserId(principal);
        SearchProfile created = searchProfileService.createSearchProfile(tenantId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    /**
     * GET /api/search-profiles
     * Получить все проекты поиска текущего арендатора.
     */
    @GetMapping
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<SearchProfile>> getMySearchProfiles(Principal principal) {
        Long tenantId = extractUserId(principal);
        return ResponseEntity.ok(searchProfileService.getMySearchProfiles(tenantId));
    }

    /**
     * GET /api/search-profiles/{id}
     * Получить конкретный проект поиска по ID.
     */
    @GetMapping("/{id}")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<SearchProfile> getSearchProfileById(
            @PathVariable Long id,
            Principal principal) {

        Long tenantId = extractUserId(principal);
        return ResponseEntity.ok(searchProfileService.getSearchProfileById(tenantId, id));
    }

    /**
     * PUT /api/search-profiles/{id}
     * Обновить проект поиска.
     */
    @PutMapping("/{id}")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<SearchProfile> updateSearchProfile(
            @PathVariable Long id,
            @RequestBody CreateSearchProfileRequest request,
            Principal principal) {

        Long tenantId = extractUserId(principal);
        return ResponseEntity.ok(searchProfileService.updateSearchProfile(tenantId, id, request));
    }

    /**
     * DELETE /api/search-profiles/{id}
     * Удалить проект поиска.
     */
    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<Void> deleteSearchProfile(
            @PathVariable Long id,
            Principal principal) {

        Long tenantId = extractUserId(principal);
        searchProfileService.deleteSearchProfile(tenantId, id);
        return ResponseEntity.noContent().build();
    }

    /**
     * GET /api/search-profiles/{id}/scored-properties
     * ⭐ Ключевой эндпоинт: получить все помещения со скорингом по конкретному профилю поиска.
     * Результат отсортирован по убыванию totalScore (лучшее совпадение — первым).
     */
    @GetMapping("/{id}/scored-properties")
    @PreAuthorize("hasRole('TENANT')")
    public ResponseEntity<List<ScoredPropertyDto>> getScoredProperties(
            @PathVariable Long id,
            Principal principal) {

        Long tenantId = extractUserId(principal);
        List<ScoredPropertyDto> scored = searchProfileService.getScoredPropertiesForProfile(tenantId, id);
        return ResponseEntity.ok(scored);
    }

    // -------------------------------------------------------------------------
    //  Вспомогательный метод
    // -------------------------------------------------------------------------
    private Long extractUserId(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Не удалось извлечь ID пользователя из токена");
    }
}
