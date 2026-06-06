package com.example.backend.controller;

import com.example.backend.dto.BusinessCategoryDto;
import com.example.backend.dto.CategoryRequest;
import com.example.backend.entity.User;
import com.example.backend.entity.enums.Role;
import com.example.backend.entity.enums.UserStatus;
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

public class GlobalAdminRoleApiTest extends BaseApiTest {

    @Test
    public void testGetAllUsers() throws Exception {
        User user = User.builder().id(101L).email("user@example.com").role(Role.TENANT).status(UserStatus.ACTIVE).build();
        Mockito.when(userRepository.findAll()).thenReturn(List.of(user));

        mockMvc.perform(get("/api/global-admin/users")
                        .with(globalAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].email").value("user@example.com"));
    }

    @Test
    public void testBlockUser() throws Exception {
        User user = User.builder().id(101L).email("user@example.com").role(Role.TENANT).status(UserStatus.ACTIVE).build();
        Mockito.when(userRepository.findById(101L)).thenReturn(Optional.of(user));
        Mockito.when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(post("/api/global-admin/users/101/block")
                        .with(globalAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("BANNED"));
    }

    @Test
    public void testUnblockUser() throws Exception {
        User user = User.builder().id(101L).email("user@example.com").role(Role.TENANT).status(UserStatus.BANNED).build();
        Mockito.when(userRepository.findById(101L)).thenReturn(Optional.of(user));
        Mockito.when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(post("/api/global-admin/users/101/unblock")
                        .with(globalAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ACTIVE"));
    }

    @Test
    public void testGetStatistics() throws Exception {
        Mockito.when(userRepository.findAll()).thenReturn(List.of());
        Mockito.when(propertyRepository.count()).thenReturn(10L);
        Mockito.when(applicationRepository.count()).thenReturn(5L);

        mockMvc.perform(get("/api/global-admin/statistics")
                        .with(globalAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalProperties").value(10))
                .andExpect(jsonPath("$.totalApplications").value(5));
    }

    @Test
    public void testGetLogs() throws Exception {
        mockMvc.perform(get("/api/global-admin/logs")
                        .with(globalAdminAuth())
                        .param("lines", "10")
                        .param("type", "stdout"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray());
    }

    @Test
    public void testCreateCategory() throws Exception {
        BusinessCategoryDto dto = new BusinessCategoryDto();
        dto.setId(10L);
        dto.setName("New Cat");
        dto.setSubCategories(List.of());
        Mockito.when(categoryService.createCategory(any(CategoryRequest.class))).thenReturn(dto);

        String requestJson = "{\"name\":\"New Cat\",\"parentId\":null}";

        mockMvc.perform(post("/api/categories")
                        .with(globalAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(10L))
                .andExpect(jsonPath("$.name").value("New Cat"));
    }

    @Test
    public void testUpdateCategory() throws Exception {
        BusinessCategoryDto dto = new BusinessCategoryDto();
        dto.setId(10L);
        dto.setName("Updated Cat");
        dto.setSubCategories(List.of());
        Mockito.when(categoryService.updateCategory(anyLong(), any(CategoryRequest.class))).thenReturn(dto);

        String requestJson = "{\"name\":\"Updated Cat\",\"parentId\":null}";

        mockMvc.perform(put("/api/categories/10")
                        .with(globalAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Updated Cat"));
    }

    @Test
    public void testDeleteCategory() throws Exception {
        mockMvc.perform(delete("/api/categories/10")
                        .with(globalAdminAuth()))
                .andExpect(status().isNoContent());
    }

    @Test
    public void testDeniedAccessForTenant() throws Exception {
        mockMvc.perform(get("/api/global-admin/users")
                        .with(tenantAuth()))
                .andExpect(status().isForbidden());
    }
}
