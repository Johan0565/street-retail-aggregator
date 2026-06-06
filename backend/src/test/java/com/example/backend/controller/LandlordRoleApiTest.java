package com.example.backend.controller;

import com.example.backend.dto.*;
import com.example.backend.entity.LandlordProfile;
import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyImage;
import com.example.backend.entity.TenantProfile;
import com.example.backend.entity.enums.ApplicationStatus;
import com.example.backend.entity.enums.Role;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;

import java.math.BigDecimal;
import java.util.List;

import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class LandlordRoleApiTest extends BaseApiTest {

    @Test
    public void testGetMyLandlordProfile() throws Exception {
        LandlordProfile profile = LandlordProfile.builder()
                .id(1L)
                .companyName("Landlord Corp")
                .build();
        Mockito.when(profileService.getLandlordProfile(anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/profiles/landlord/me")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.companyName").value("Landlord Corp"));
    }

    @Test
    public void testUpdateMyLandlordProfile() throws Exception {
        LandlordProfile profile = LandlordProfile.builder()
                .id(1L)
                .companyName("Landlord Corp Updated")
                .build();
        Mockito.when(profileService.updateLandlordProfile(anyLong(), any(UpdateLandlordProfileRequest.class))).thenReturn(profile);

        String requestJson = "{\"companyName\":\"Landlord Corp Updated\"}";

        mockMvc.perform(put("/api/profiles/landlord/me")
                        .with(landlordAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.companyName").value("Landlord Corp Updated"));
    }

    @Test
    public void testCreateProperty() throws Exception {
        Property property = Property.builder().id(1L).title("New Shop").pricePerMonth(BigDecimal.valueOf(60000.0)).build();
        Mockito.when(propertyService.createProperty(anyLong(), any(CreatePropertyRequest.class))).thenReturn(property);

        String requestJson = "{\"title\":\"New Shop\",\"description\":\"Shop desc\",\"address\":\"Address\",\"pricePerMonth\":60000.0,\"area\":55.0,\"lat\":55.1,\"lon\":37.1}";

        mockMvc.perform(post("/api/properties")
                        .with(landlordAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1L))
                .andExpect(jsonPath("$.title").value("New Shop"));
    }

    @Test
    public void testGetMyProperties() throws Exception {
        Property property = Property.builder().id(1L).title("Shop").build();
        Mockito.when(propertyService.getMyProperties(anyLong())).thenReturn(List.of(property));

        mockMvc.perform(get("/api/properties/my")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testUpdateProperty() throws Exception {
        Property property = Property.builder().id(1L).title("Updated Shop").build();
        Mockito.when(propertyService.updateProperty(anyLong(), anyLong(), any(CreatePropertyRequest.class))).thenReturn(property);

        String requestJson = "{\"title\":\"Updated Shop\",\"description\":\"Shop desc\",\"address\":\"Address\",\"pricePerMonth\":60000.0,\"area\":55.0,\"lat\":55.1,\"lon\":37.1}";

        mockMvc.perform(put("/api/properties/1")
                        .with(landlordAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("Updated Shop"));
    }

    @Test
    public void testDeleteProperty() throws Exception {
        mockMvc.perform(delete("/api/properties/1")
                        .with(landlordAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testUploadPropertyImages() throws Exception {
        PropertyImage img = PropertyImage.builder().id(1L).imageUrl("http://image.url").isMain(true).build();
        Mockito.when(propertyImageService.upload(anyLong(), anyLong(), anyList())).thenReturn(List.of(img));

        MockMultipartFile file = new MockMultipartFile("files", "image.png", "image/png", "image-bytes".getBytes());

        mockMvc.perform(multipart("/api/properties/1/images")
                        .file(file)
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].imageUrl").value("http://image.url"));
    }

    @Test
    public void testDeletePropertyImage() throws Exception {
        mockMvc.perform(delete("/api/properties/1/images/2")
                        .with(landlordAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testSetMainImage() throws Exception {
        mockMvc.perform(put("/api/properties/1/images/2/main")
                        .with(landlordAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetIncomingApplications() throws Exception {
        ApplicationResponseDto app = ApplicationResponseDto.builder()
                .id(1L)
                .property(ApplicationResponseDto.PropertyShortInfo.builder().id(1L).title("My Shop").build())
                .build();
        Mockito.when(applicationService.getLandlordApplications(anyLong())).thenReturn(List.of(app));

        mockMvc.perform(get("/api/applications/incoming")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testUpdateApplicationStatus() throws Exception {
        ApplicationResponseDto app = ApplicationResponseDto.builder().id(1L).status(ApplicationStatus.ACCEPTED).build();
        Mockito.when(applicationService.updateApplicationStatus(anyLong(), anyLong(), any(ApplicationStatus.class), any())).thenReturn(app);

        String requestJson = "{\"status\":\"ACCEPTED\"}";

        mockMvc.perform(patch("/api/applications/1/status")
                        .with(landlordAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ACCEPTED"));
    }

    @Test
    public void testDeleteApplicationByLandlord() throws Exception {
        mockMvc.perform(delete("/api/applications/1")
                        .with(landlordAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetApplicationByIdByLandlord() throws Exception {
        ApplicationResponseDto app = ApplicationResponseDto.builder().id(1L).build();
        Mockito.when(applicationService.getApplicationById(anyLong(), anyLong(), any(Role.class))).thenReturn(app);

        mockMvc.perform(get("/api/applications/1")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testGetLandlordAnalytics() throws Exception {
        AnalyticsDto dto = AnalyticsDto.builder().totalViewsLast30Days(50).totalFavoritesLast30Days(10).build();
        Mockito.when(analyticsService.getLandlordAnalytics(anyLong())).thenReturn(dto);

        mockMvc.perform(get("/api/analytics/my-properties")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalViewsLast30Days").value(50));
    }

    @Test
    public void testGetPropertyAnalytics() throws Exception {
        AnalyticsDto dto = AnalyticsDto.builder().totalViewsLast30Days(20).totalFavoritesLast30Days(5).build();
        Mockito.when(analyticsService.isOwner(anyLong(), anyLong())).thenReturn(true);
        Mockito.when(analyticsService.getPropertyAnalytics(anyLong())).thenReturn(dto);

        mockMvc.perform(get("/api/analytics/property/1")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalViewsLast30Days").value(20));
    }

    @Test
    public void testLogPropertyView() throws Exception {
        mockMvc.perform(post("/api/analytics/view/1")
                        .with(landlordAuth()))
                .andExpect(status().isOk());
    }

    @Test
    public void testGetTenantProfileById() throws Exception {
        TenantProfile profile = TenantProfile.builder().id(1L).name("John Tenant").build();
        Mockito.when(profileService.getTenantProfile(anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/profiles/tenant/1")
                        .with(landlordAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("John Tenant"));
    }
}
