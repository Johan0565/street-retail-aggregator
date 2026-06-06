package com.example.backend.controller;

import com.example.backend.dto.*;
import com.example.backend.entity.Property;
import com.example.backend.entity.enums.Role;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;

import java.math.BigDecimal;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class PublicApiTest extends BaseApiTest {

    @Test
    public void testRegister() throws Exception {
        AuthResponse mockResponse = AuthResponse.builder()
                .token("register-token")
                .role(Role.TENANT)
                .email("newuser@example.com")
                .build();
        Mockito.when(authService.register(any(RegisterRequest.class))).thenReturn(mockResponse);

        String requestJson = "{\"email\":\"newuser@example.com\",\"password\":\"password\",\"role\":\"TENANT\"}";

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("register-token"))
                .andExpect(jsonPath("$.email").value("newuser@example.com"));
    }

    @Test
    public void testLogin() throws Exception {
        AuthResponse mockResponse = AuthResponse.builder()
                .token("login-token")
                .role(Role.LANDLORD)
                .email("landlord@example.com")
                .build();
        Mockito.when(authService.login(any(LoginRequest.class))).thenReturn(mockResponse);

        String requestJson = "{\"email\":\"landlord@example.com\",\"password\":\"password\"}";

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("login-token"))
                .andExpect(jsonPath("$.role").value("LANDLORD"));
    }

    @Test
    public void testVerifyEmail() throws Exception {
        AuthResponse mockResponse = AuthResponse.builder()
                .token("verified-token")
                .role(Role.TENANT)
                .email("tenant@example.com")
                .build();
        Mockito.when(authService.verifyEmail(any(VerifyEmailRequest.class))).thenReturn(mockResponse);

        String requestJson = "{\"email\":\"tenant@example.com\",\"code\":\"123456\"}";

        mockMvc.perform(post("/api/auth/verify")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("verified-token"));
    }

    @Test
    public void testResendCode() throws Exception {
        AuthResponse mockResponse = AuthResponse.builder()
                .email("tenant@example.com")
                .build();
        Mockito.when(authService.resendCode(anyString())).thenReturn(mockResponse);

        mockMvc.perform(post("/api/auth/resend-code")
                        .param("email", "tenant@example.com"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("tenant@example.com"));
    }

    @Test
    public void testGetAllProperties() throws Exception {
        Property property = Property.builder()
                .id(1L)
                .title("Beautiful Shop")
                .address("Mock Address")
                .pricePerMonth(BigDecimal.valueOf(50000.0))
                .build();
        Mockito.when(propertyService.getAllPublishedProperties()).thenReturn(List.of(property));

        mockMvc.perform(get("/api/properties"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L))
                .andExpect(jsonPath("$[0].title").value("Beautiful Shop"));
    }

    @Test
    public void testGetPropertyById() throws Exception {
        Property property = Property.builder()
                .id(1L)
                .title("Beautiful Shop")
                .address("Mock Address")
                .pricePerMonth(BigDecimal.valueOf(50000.0))
                .build();
        Mockito.when(propertyService.getPropertyById(1L)).thenReturn(property);

        mockMvc.perform(get("/api/properties/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L))
                .andExpect(jsonPath("$.title").value("Beautiful Shop"));
    }

    @Test
    public void testGetCategoryTree() throws Exception {
        BusinessCategoryDto dto = new BusinessCategoryDto();
        dto.setId(1L);
        dto.setName("Retail");
        dto.setSubCategories(List.of());
        Mockito.when(categoryService.getCategoryTree()).thenReturn(List.of(dto));

        mockMvc.perform(get("/api/categories"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L))
                .andExpect(jsonPath("$[0].name").value("Retail"));
    }

    @Test
    public void testGetCategoriesFlat() throws Exception {
        BusinessCategoryDto dto = new BusinessCategoryDto();
        dto.setId(1L);
        dto.setName("Retail");
        Mockito.when(categoryService.getAllFlat()).thenReturn(List.of(dto));

        mockMvc.perform(get("/api/categories/flat"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testGetCategoryById() throws Exception {
        BusinessCategoryDto dto = new BusinessCategoryDto();
        dto.setId(1L);
        dto.setName("Retail");
        Mockito.when(categoryService.getCategoryById(1L)).thenReturn(dto);

        mockMvc.perform(get("/api/categories/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1L))
                .andExpect(jsonPath("$.name").value("Retail"));
    }
}
