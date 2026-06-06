package com.example.backend.controller;

import com.example.backend.dto.BuildingSpecsRequest;
import com.example.backend.entity.AccessibilityZone;
import com.example.backend.entity.MetroStation;
import com.example.backend.entity.Property;
import com.example.backend.entity.enums.VerificationStatus;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;

import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class PropertyAdminRoleApiTest extends BaseApiTest {

    @Test
    public void testGetAllProperties() throws Exception {
        Property property = Property.builder().id(1L).title("Aggregator Shop").build();
        Mockito.when(propertyRepository.findAll()).thenReturn(List.of(property));

        mockMvc.perform(get("/api/property-admin/properties")
                        .with(propertyAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].title").value("Aggregator Shop"));
    }

    @Test
    public void testUpdateDocumentVerificationStatus() throws Exception {
        Property property = Property.builder().id(1L).documentVerificationStatus(VerificationStatus.PENDING).build();
        Mockito.when(propertyRepository.findById(1L)).thenReturn(Optional.of(property));
        Mockito.when(propertyRepository.save(any(Property.class))).thenAnswer(inv -> inv.getArgument(0));

        mockMvc.perform(patch("/api/property-admin/properties/1/document-status")
                        .with(propertyAdminAuth())
                        .param("status", "VERIFIED"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.documentVerificationStatus").value("VERIFIED"));
    }

    @Test
    public void testUpdateAddressConfirmationStatus() throws Exception {
        Property property = Property.builder().id(1L).addressConfirmationStatus(VerificationStatus.PENDING).build();
        Mockito.when(propertyRepository.findById(1L)).thenReturn(Optional.of(property));
        Mockito.when(propertyRepository.save(any(Property.class))).thenAnswer(inv -> inv.getArgument(0));

        mockMvc.perform(patch("/api/property-admin/properties/1/address-status")
                        .with(propertyAdminAuth())
                        .param("status", "REJECTED"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.addressConfirmationStatus").value("REJECTED"));
    }

    @Test
    public void testUpdateBuildingSpecs() throws Exception {
        Property property = Property.builder().id(1L).buildingName("Old Name").build();
        Mockito.when(propertyRepository.findById(1L)).thenReturn(Optional.of(property));
        Mockito.when(propertyRepository.save(any(Property.class))).thenAnswer(inv -> inv.getArgument(0));

        String requestJson = "{\"buildingName\":\"New Business Center\",\"powerKw\":25.0,\"hasWater\":true}";

        mockMvc.perform(put("/api/property-admin/properties/1/building-specs")
                        .with(propertyAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.buildingName").value("New Business Center"))
                .andExpect(jsonPath("$.powerKw").value(25.0));
    }

    @Test
    public void testGetAllMetroStations() throws Exception {
        MetroStation station = MetroStation.builder().id(1L).name("Centrale").build();
        Mockito.when(metroStationRepository.findAll()).thenReturn(List.of(station));

        mockMvc.perform(get("/api/property-admin/metro-stations")
                        .with(propertyAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Centrale"));
    }

    @Test
    public void testCreateMetroStation() throws Exception {
        MetroStation station = MetroStation.builder().id(1L).name("South").lineName("Red").build();
        Mockito.when(metroStationRepository.save(any(MetroStation.class))).thenReturn(station);

        String requestJson = "{\"name\":\"South\",\"lineName\":\"Red\",\"latitude\":55.0,\"longitude\":37.0}";

        mockMvc.perform(post("/api/property-admin/metro-stations")
                        .with(propertyAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1L))
                .andExpect(jsonPath("$.name").value("South"));
    }

    @Test
    public void testUpdateMetroStation() throws Exception {
        MetroStation station = MetroStation.builder().id(1L).name("South").build();
        Mockito.when(metroStationRepository.findById(1L)).thenReturn(Optional.of(station));
        Mockito.when(metroStationRepository.save(any(MetroStation.class))).thenAnswer(inv -> inv.getArgument(0));

        String requestJson = "{\"name\":\"South Updated\",\"lineName\":\"Red\",\"latitude\":55.0,\"longitude\":37.0}";

        mockMvc.perform(put("/api/property-admin/metro-stations/1")
                        .with(propertyAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("South Updated"));
    }

    @Test
    public void testDeleteMetroStation() throws Exception {
        mockMvc.perform(delete("/api/property-admin/metro-stations/1")
                        .with(propertyAdminAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetAllAccessibilityZones() throws Exception {
        AccessibilityZone zone = AccessibilityZone.builder().id(1L).name("Zone A").build();
        Mockito.when(accessibilityZoneRepository.findAll()).thenReturn(List.of(zone));

        mockMvc.perform(get("/api/property-admin/accessibility-zones")
                        .with(propertyAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Zone A"));
    }

    @Test
    public void testCreateAccessibilityZone() throws Exception {
        AccessibilityZone zone = AccessibilityZone.builder().id(1L).name("Zone B").build();
        Mockito.when(accessibilityZoneRepository.save(any(AccessibilityZone.class))).thenReturn(zone);

        String requestJson = "{\"name\":\"Zone B\",\"minTimeToMetro\":5,\"maxTimeToMetro\":10,\"accessibilityScore\":9.0}";

        mockMvc.perform(post("/api/property-admin/accessibility-zones")
                        .with(propertyAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testUpdateAccessibilityZone() throws Exception {
        AccessibilityZone zone = AccessibilityZone.builder().id(1L).name("Zone B").build();
        Mockito.when(accessibilityZoneRepository.findById(1L)).thenReturn(Optional.of(zone));
        Mockito.when(accessibilityZoneRepository.save(any(AccessibilityZone.class))).thenAnswer(inv -> inv.getArgument(0));

        String requestJson = "{\"name\":\"Zone B Updated\",\"minTimeToMetro\":5,\"maxTimeToMetro\":10,\"accessibilityScore\":9.5}";

        mockMvc.perform(put("/api/property-admin/accessibility-zones/1")
                        .with(propertyAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Zone B Updated"));
    }

    @Test
    public void testDeleteAccessibilityZone() throws Exception {
        mockMvc.perform(delete("/api/property-admin/accessibility-zones/1")
                        .with(propertyAdminAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testDeniedAccessForTenant() throws Exception {
        mockMvc.perform(get("/api/property-admin/properties")
                        .with(tenantAuth()))
                .andExpect(status().isForbidden());
    }
}
