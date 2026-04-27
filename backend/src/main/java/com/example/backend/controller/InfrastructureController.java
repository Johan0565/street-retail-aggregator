package com.example.backend.controller;

import com.example.backend.dto.PoiDto;
import com.example.backend.service.InfrastructureService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/infrastructure")
@RequiredArgsConstructor
public class InfrastructureController {

    private final InfrastructureService infrastructureService;

    @GetMapping
    public ResponseEntity<List<PoiDto>> getInfrastructure(
            @RequestParam double lat,
            @RequestParam double lon,
            @RequestParam(defaultValue = "500") int radius,
            @RequestParam(required = false) Long profileId) {
        return ResponseEntity.ok(infrastructureService.getInfrastructureNearby(lat, lon, radius, profileId));
    }
}
