package com.example.backend.controller;

import com.example.backend.dto.BuildingSpecsRequest;
import com.example.backend.entity.AccessibilityZone;
import com.example.backend.entity.MetroStation;
import com.example.backend.entity.Property;
import com.example.backend.entity.enums.VerificationStatus;
import com.example.backend.repository.AccessibilityZoneRepository;
import com.example.backend.repository.MetroStationRepository;
import com.example.backend.repository.PropertyRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/property-admin")
@RequiredArgsConstructor
@PreAuthorize("hasAnyRole('ADMIN', 'PROPERTY_ADMIN')")
public class PropertyAdminController {

    private final PropertyRepository propertyRepository;
    private final MetroStationRepository metroStationRepository;
    private final AccessibilityZoneRepository accessibilityZoneRepository;

    @GetMapping("/properties")
    public ResponseEntity<List<Property>> getAllProperties() {
        return ResponseEntity.ok(propertyRepository.findAll());
    }

    @PatchMapping("/properties/{propertyId}/document-status")
    public ResponseEntity<Property> updateDocumentVerificationStatus(
            @PathVariable Long propertyId,
            @RequestParam VerificationStatus status) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Property not found"));
        property.setDocumentVerificationStatus(status);
        return ResponseEntity.ok(propertyRepository.save(property));
    }

    @PatchMapping("/properties/{propertyId}/address-status")
    public ResponseEntity<Property> updateAddressConfirmationStatus(
            @PathVariable Long propertyId,
            @RequestParam VerificationStatus status) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Property not found"));
        property.setAddressConfirmationStatus(status);
        return ResponseEntity.ok(propertyRepository.save(property));
    }

    @PutMapping("/properties/{propertyId}/building-specs")
    public ResponseEntity<Property> updateBuildingSpecs(
            @PathVariable Long propertyId,
            @RequestBody BuildingSpecsRequest request) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Property not found"));

        if (request.getBuildingName() != null) property.setBuildingName(request.getBuildingName());
        if (request.getBuildingClass() != null) property.setBuildingClass(request.getBuildingClass());
        if (request.getBuildYear() != null) property.setBuildYear(request.getBuildYear());
        if (request.getTotalFloors() != null) property.setTotalFloors(request.getTotalFloors());
        if (request.getPowerKw() != null) property.setPowerKw(request.getPowerKw());
        if (request.getHasWater() != null) property.setHasWater(request.getHasWater());
        if (request.getHasVentilation() != null) property.setHasVentilation(request.getHasVentilation());
        if (request.getHasSeparateEntrance() != null) property.setHasSeparateEntrance(request.getHasSeparateEntrance());
        if (request.getRepairState() != null) property.setRepairState(request.getRepairState());
        if (request.getCeilingHeight() != null) property.setCeilingHeight(request.getCeilingHeight());
        if (request.getLayout() != null) property.setLayout(request.getLayout());
        if (request.getAccessType() != null) property.setAccessType(request.getAccessType());
        if (request.getHeatingType() != null) property.setHeatingType(request.getHeatingType());
        if (request.getFurnitureState() != null) property.setFurnitureState(request.getFurnitureState());

        return ResponseEntity.ok(propertyRepository.save(property));
    }

    // --- Metro Station CRUD ---

    @GetMapping("/metro-stations")
    public ResponseEntity<List<MetroStation>> getAllMetroStations() {
        return ResponseEntity.ok(metroStationRepository.findAll());
    }

    @PostMapping("/metro-stations")
    public ResponseEntity<MetroStation> createMetroStation(@RequestBody MetroStation station) {
        return ResponseEntity.status(HttpStatus.CREATED).body(metroStationRepository.save(station));
    }

    @PutMapping("/metro-stations/{id}")
    public ResponseEntity<MetroStation> updateMetroStation(@PathVariable Long id, @RequestBody MetroStation updated) {
        MetroStation existing = metroStationRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Metro station not found"));
        existing.setName(updated.getName());
        existing.setLineName(updated.getLineName());
        existing.setLatitude(updated.getLatitude());
        existing.setLongitude(updated.getLongitude());
        return ResponseEntity.ok(metroStationRepository.save(existing));
    }

    @DeleteMapping("/metro-stations/{id}")
    public ResponseEntity<Void> deleteMetroStation(@PathVariable Long id) {
        metroStationRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    // --- Accessibility Zone CRUD ---

    @GetMapping("/accessibility-zones")
    public ResponseEntity<List<AccessibilityZone>> getAllAccessibilityZones() {
        return ResponseEntity.ok(accessibilityZoneRepository.findAll());
    }

    @PostMapping("/accessibility-zones")
    public ResponseEntity<AccessibilityZone> createAccessibilityZone(@RequestBody AccessibilityZone zone) {
        return ResponseEntity.status(HttpStatus.CREATED).body(accessibilityZoneRepository.save(zone));
    }

    @PutMapping("/accessibility-zones/{id}")
    public ResponseEntity<AccessibilityZone> updateAccessibilityZone(@PathVariable Long id, @RequestBody AccessibilityZone updated) {
        AccessibilityZone existing = accessibilityZoneRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Accessibility zone not found"));
        existing.setName(updated.getName());
        existing.setMinTimeToMetro(updated.getMinTimeToMetro());
        existing.setMaxTimeToMetro(updated.getMaxTimeToMetro());
        existing.setAccessibilityScore(updated.getAccessibilityScore());
        return ResponseEntity.ok(accessibilityZoneRepository.save(existing));
    }

    @DeleteMapping("/accessibility-zones/{id}")
    public ResponseEntity<Void> deleteAccessibilityZone(@PathVariable Long id) {
        accessibilityZoneRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
