package com.example.backend.controller;

import com.example.backend.dto.*;
import com.example.backend.entity.Property;
import com.example.backend.entity.SearchProfile;
import com.example.backend.entity.TenantProfile;
import com.example.backend.entity.LandlordProfile;
import com.example.backend.entity.enums.Role;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;

import java.util.List;

import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class TenantRoleApiTest extends BaseApiTest {

    @Test
    public void testGetMyTenantProfile() throws Exception {
        TenantProfile profile = TenantProfile.builder()
                .id(1L)
                .name("John Tenant")
                .build();
        Mockito.when(profileService.getTenantProfile(anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/profiles/tenant/me")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("John Tenant"));
    }

    @Test
    public void testUpdateMyTenantProfile() throws Exception {
        TenantProfile profile = TenantProfile.builder()
                .id(1L)
                .name("John Updated")
                .build();
        Mockito.when(profileService.updateTenantProfile(anyLong(), any(UpdateTenantProfileRequest.class))).thenReturn(profile);

        String requestJson = "{\"name\":\"John Updated\"}";

        mockMvc.perform(put("/api/profiles/tenant/me")
                        .with(tenantAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("John Updated"));
    }

    @Test
    public void testGetPropertyScore() throws Exception {
        ScoredPropertyDto score = ScoredPropertyDto.builder()
                .property(Property.builder().id(1L).build())
                .totalScore(8)
                .build();
        Mockito.when(propertyService.scorePropertyForTenant(anyLong(), anyLong(), any(), anyBoolean())).thenReturn(score);

        mockMvc.perform(get("/api/properties/1/score")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalScore").value(8));
    }

    @Test
    public void testGetRecommendedProperties() throws Exception {
        Property property = Property.builder().id(1L).title("Shop").build();
        Mockito.when(propertyService.getRecommendedPropertiesForTenant(anyLong())).thenReturn(List.of(property));

        mockMvc.perform(get("/api/properties/recommended")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testExplainPropertyScore() throws Exception {
        ScoredPropertyDto score = ScoredPropertyDto.builder().property(Property.builder().id(1L).build()).build();
        SearchProfile profile = SearchProfile.builder().id(2L).build();
        ScoreExplainResponse response = new ScoreExplainResponse("Excellent location!");

        Mockito.when(propertyService.scorePropertyForTenant(anyLong(), anyLong(), any())).thenReturn(score);
        Mockito.when(propertyService.findProfileForTenant(anyLong(), any())).thenReturn(profile);
        Mockito.when(openRouterAiService.explainScore(any(), any())).thenReturn(response);

        mockMvc.perform(get("/api/properties/1/score-explain")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.explanation").value("Excellent location!"));
    }

    @Test
    public void testAddAndRemoveFavorite() throws Exception {
        mockMvc.perform(post("/api/properties/1/favorite")
                        .with(tenantAuth()))
                .andExpect(status().isOk());

        mockMvc.perform(delete("/api/properties/1/favorite")
                        .with(tenantAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetMyFavorites() throws Exception {
        Property property = Property.builder().id(1L).title("Favorite Shop").build();
        Mockito.when(propertyService.getFavorites(anyLong())).thenReturn(List.of(property));

        mockMvc.perform(get("/api/properties/favorites")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].title").value("Favorite Shop"));
    }

    @Test
    public void testCreateApplication() throws Exception {
        ApplicationResponseDto response = ApplicationResponseDto.builder()
                .id(1L)
                .property(ApplicationResponseDto.PropertyShortInfo.builder().id(1L).title("Shop").build())
                .build();
        Mockito.when(applicationService.createApplication(anyLong(), anyLong(), anyString())).thenReturn(response);

        String requestJson = "{\"propertyId\":1,\"coverLetter\":\"Hello\"}";

        mockMvc.perform(post("/api/applications")
                        .with(tenantAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testGetTenantApplications() throws Exception {
        ApplicationResponseDto app = ApplicationResponseDto.builder().id(1L).build();
        Mockito.when(applicationService.getTenantApplications(anyLong())).thenReturn(List.of(app));

        mockMvc.perform(get("/api/applications/my-requests")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testDeleteApplication() throws Exception {
        mockMvc.perform(delete("/api/applications/1")
                        .with(tenantAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetApplicationById() throws Exception {
        ApplicationResponseDto app = ApplicationResponseDto.builder().id(1L).build();
        Mockito.when(applicationService.getApplicationById(anyLong(), anyLong(), any(Role.class))).thenReturn(app);

        mockMvc.perform(get("/api/applications/1")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testCreateSearchProfile() throws Exception {
        SearchProfile profile = SearchProfile.builder().id(1L).name("Profile").build();
        Mockito.when(searchProfileService.createSearchProfile(anyLong(), any(CreateSearchProfileRequest.class))).thenReturn(profile);

        String requestJson = "{\"name\":\"Profile\",\"minArea\":10.0,\"maxArea\":100.0,\"maxPricePerMonth\":50000.0,\"preferredPowerKw\":15.0,\"hasWater\":true,\"hasVentilation\":true,\"hasSeparateEntrance\":true,\"preferredAccessibilityZoneIds\":[],\"preferredMetroStationIds\":[],\"businessCategoryId\":1}";

        mockMvc.perform(post("/api/search-profiles")
                        .with(tenantAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testGetMySearchProfiles() throws Exception {
        SearchProfile profile = SearchProfile.builder().id(1L).name("Profile").build();
        Mockito.when(searchProfileService.getMySearchProfiles(anyLong())).thenReturn(List.of(profile));

        mockMvc.perform(get("/api/search-profiles")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testGetSearchProfileById() throws Exception {
        SearchProfile profile = SearchProfile.builder().id(1L).build();
        Mockito.when(searchProfileService.getSearchProfileById(anyLong(), anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/search-profiles/1")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testUpdateSearchProfile() throws Exception {
        SearchProfile profile = SearchProfile.builder().id(1L).name("Updated Profile").build();
        Mockito.when(searchProfileService.updateSearchProfile(anyLong(), anyLong(), any(CreateSearchProfileRequest.class))).thenReturn(profile);

        String requestJson = "{\"name\":\"Updated Profile\",\"minArea\":10.0,\"maxArea\":100.0,\"maxPricePerMonth\":50000.0,\"preferredPowerKw\":15.0,\"hasWater\":true,\"hasVentilation\":true,\"hasSeparateEntrance\":true,\"preferredAccessibilityZoneIds\":[],\"preferredMetroStationIds\":[],\"businessCategoryId\":1}";

        mockMvc.perform(put("/api/search-profiles/1")
                        .with(tenantAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L))
                .andExpect(jsonPath("$.name").value("Updated Profile"));
    }

    @Test
    public void testDeleteSearchProfile() throws Exception {
        mockMvc.perform(delete("/api/search-profiles/1")
                        .with(tenantAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetScoredPropertiesForProfile() throws Exception {
        ScoredPropertyDto score = ScoredPropertyDto.builder()
                .property(Property.builder().id(1L).build())
                .totalScore(9)
                .build();
        Mockito.when(searchProfileService.getScoredPropertiesForProfile(anyLong(), anyLong())).thenReturn(List.of(score));

        mockMvc.perform(get("/api/search-profiles/1/scored-properties")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].property.id").value(1L));
    }

    @Test
    public void testUploadAvatar() throws Exception {
        Mockito.when(profileService.uploadAvatar(anyLong(), any())).thenReturn("http://avatar.url");
        MockMultipartFile file = new MockMultipartFile("file", "avatar.png", "image/png", "avatar-bytes".getBytes());

        mockMvc.perform(multipart("/api/profiles/me/avatar")
                        .file(file)
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avatarUrl").value("http://avatar.url"));
    }

    @Test
    public void testDeleteAvatar() throws Exception {
        mockMvc.perform(delete("/api/profiles/me/avatar")
                        .with(tenantAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testGetTenantProfileById() throws Exception {
        TenantProfile profile = TenantProfile.builder().id(1L).name("John").build();
        Mockito.when(profileService.getTenantProfile(anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/profiles/tenant/1")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("John"));
    }

    @Test
    public void testGetLandlordProfileById() throws Exception {
        LandlordProfile profile = LandlordProfile.builder().id(1L).companyName("LLC Landlord").build();
        Mockito.when(profileService.getLandlordProfile(anyLong())).thenReturn(profile);

        mockMvc.perform(get("/api/profiles/landlord/1")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.companyName").value("LLC Landlord"));
    }

    @Test
    public void testGetOrCreateChatRoom() throws Exception {
        ChatRoomDto dto = ChatRoomDto.builder().id(1L).applicationId(2L).build();
        Mockito.when(chatService.getOrCreateChatRoom(anyLong())).thenReturn(dto);

        mockMvc.perform(get("/api/chat/applications/2/room")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L));
    }

    @Test
    public void testGetMyChatRooms() throws Exception {
        ChatRoomDto dto = ChatRoomDto.builder().id(1L).build();
        Mockito.when(chatService.getUserChatRooms(anyLong())).thenReturn(List.of(dto));

        mockMvc.perform(get("/api/chat/rooms")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testGetChatMessages() throws Exception {
        ChatMessageDto msg = ChatMessageDto.builder().id(1L).content("Hello").build();
        Mockito.when(chatService.getChatMessages(anyLong())).thenReturn(List.of(msg));

        mockMvc.perform(get("/api/chat/rooms/1/messages")
                        .with(tenantAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].content").value("Hello"));
    }

    @Test
    public void testSendChatMessage() throws Exception {
        ChatMessageDto msg = ChatMessageDto.builder().id(1L).content("Hello back").build();
        Mockito.when(chatService.saveMessage(anyLong(), anyLong(), anyString())).thenReturn(msg);

        String requestJson = "{\"content\":\"Hello back\"}";

        mockMvc.perform(post("/api/chat/rooms/1/messages")
                        .with(tenantAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value("Hello back"));
    }

    @Test
    public void testGetInfrastructure() throws Exception {
        PoiDto poi = PoiDto.builder().name("Supermarket").category("grocery").distanceMeters(100.0).build();
        Mockito.when(infrastructureService.getInfrastructureNearby(anyDouble(), anyDouble(), anyInt())).thenReturn(List.of(poi));

        mockMvc.perform(get("/api/infrastructure")
                        .with(tenantAuth())
                        .param("lat", "55.0")
                        .param("lon", "37.0")
                        .param("radius", "500"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Supermarket"));
    }
}
