package com.example.backend.controller;

import com.example.backend.entity.*;
import com.example.backend.entity.enums.ApplicationStatus;
import com.example.backend.entity.enums.Role;
import com.example.backend.entity.enums.UserStatus;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.MediaType;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class DealAdminRoleApiTest extends BaseApiTest {

    @Test
    public void testGetAllChats() throws Exception {
        ChatRoom room = ChatRoom.builder().id(1L).isDisputed(false).build();
        Mockito.when(chatRoomRepository.findAll()).thenReturn(List.of(room));

        mockMvc.perform(get("/api/deal-admin/chats")
                        .with(dealAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L));
    }

    @Test
    public void testGetChatMessages() throws Exception {
        ChatRoom room = ChatRoom.builder().id(1L).build();
        User sender = User.builder().id(101L).email("sender@example.com").build();
        ChatMessage msg = ChatMessage.builder().id(10L).chatRoom(room).sender(sender).content("Hello").isRead(false).build();
        Mockito.when(chatMessageRepository.findByChatRoomIdOrderByTimestampAsc(1L)).thenReturn(List.of(msg));

        mockMvc.perform(get("/api/deal-admin/chats/1/messages")
                        .with(dealAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].content").value("Hello"));
    }

    @Test
    public void testSendModeratorMessage() throws Exception {
        ChatRoom room = ChatRoom.builder().id(1L).build();
        User moderator = User.builder().id(300L).email("moderator@example.com").build();
        ChatMessage saved = ChatMessage.builder().id(10L).chatRoom(room).sender(moderator).content("[Модератор moderator@example.com]: Warning").isRead(false).build();

        Mockito.when(chatRoomRepository.findById(1L)).thenReturn(Optional.of(room));
        Mockito.when(chatMessageRepository.save(any(ChatMessage.class))).thenReturn(saved);

        String requestJson = "{\"content\":\"Warning\"}";

        mockMvc.perform(post("/api/deal-admin/chats/1/messages")
                        .with(dealAdminAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(requestJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value("[Модератор moderator@example.com]: Warning"));
    }

    @Test
    public void testOpenDispute() throws Exception {
        ChatRoom room = ChatRoom.builder().id(1L).isDisputed(false).build();
        Mockito.when(chatRoomRepository.findById(1L)).thenReturn(Optional.of(room));
        Mockito.when(chatRoomRepository.save(any(ChatRoom.class))).thenAnswer(inv -> inv.getArgument(0));

        mockMvc.perform(post("/api/deal-admin/chats/1/dispute")
                        .with(dealAdminAuth())
                        .param("notes", "Price dispute"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isDisputed").value(true))
                .andExpect(jsonPath("$.disputeNotes").value("Price dispute"));
    }

    @Test
    public void testResolveDispute() throws Exception {
        ChatRoom room = ChatRoom.builder().id(1L).isDisputed(true).disputeResolved(false).build();
        Mockito.when(chatRoomRepository.findById(1L)).thenReturn(Optional.of(room));
        Mockito.when(chatRoomRepository.save(any(ChatRoom.class))).thenAnswer(inv -> inv.getArgument(0));

        mockMvc.perform(patch("/api/deal-admin/chats/1/resolve-dispute")
                        .with(dealAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isDisputed").value(false))
                .andExpect(jsonPath("$.disputeResolved").value(true));
    }

    @Test
    public void testConfirmLeaseDeal() throws Exception {
        Application application = Application.builder()
                .id(1L)
                .status(ApplicationStatus.ACCEPTED)
                .isDealConfirmed(false)
                .build();
        Mockito.when(applicationRepository.findById(1L)).thenReturn(Optional.of(application));
        Mockito.when(applicationRepository.save(any(Application.class))).thenAnswer(inv -> inv.getArgument(0));

        mockMvc.perform(post("/api/deal-admin/applications/1/confirm-deal")
                        .with(dealAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isDealConfirmed").value(true));
    }

    @Test
    public void testGetTransactionReport() throws Exception {
        TenantProfile tp = TenantProfile.builder().name("Tenant Name").build();
        User tenant = User.builder().email("tenant@example.com").tenantProfile(tp).build();
        LandlordProfile lp = LandlordProfile.builder().companyName("Landlord Corp").build();
        User landlord = User.builder().email("landlord@example.com").landlordProfile(lp).build();
        Property property = Property.builder().id(2L).title("Shop").address("Address").pricePerMonth(BigDecimal.valueOf(10000.0)).landlord(landlord).build();

        Application application = Application.builder()
                .id(1L)
                .status(ApplicationStatus.ACCEPTED)
                .isDealConfirmed(true)
                .dealConfirmedAt(LocalDateTime.now())
                .tenant(tenant)
                .property(property)
                .build();

        Mockito.when(applicationRepository.findAll()).thenReturn(List.of(application));

        mockMvc.perform(get("/api/deal-admin/transactions/report")
                        .with(dealAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].applicationId").value(1L))
                .andExpect(jsonPath("$[0].tenantEmail").value("tenant@example.com"));
    }

    @Test
    public void testDownloadTransactionReportCsv() throws Exception {
        TenantProfile tp = TenantProfile.builder().name("Tenant Name").build();
        User tenant = User.builder().email("tenant@example.com").tenantProfile(tp).build();
        LandlordProfile lp = LandlordProfile.builder().companyName("Landlord Corp").build();
        User landlord = User.builder().email("landlord@example.com").landlordProfile(lp).build();
        Property property = Property.builder().id(2L).title("Shop").address("Address").pricePerMonth(BigDecimal.valueOf(10000.0)).landlord(landlord).build();

        Application application = Application.builder()
                .id(1L)
                .status(ApplicationStatus.ACCEPTED)
                .isDealConfirmed(true)
                .dealConfirmedAt(LocalDateTime.now())
                .tenant(tenant)
                .property(property)
                .build();

        Mockito.when(applicationRepository.findAll()).thenReturn(List.of(application));

        mockMvc.perform(get("/api/deal-admin/transactions/report/csv")
                        .with(dealAdminAuth()))
                .andExpect(status().isOk())
                .andExpect(result -> {
                    String content = result.getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
                    org.junit.jupiter.api.Assertions.assertTrue(content.contains("tenant@example.com"));
                    org.junit.jupiter.api.Assertions.assertTrue(content.contains("Landlord Corp"));
                });
    }

    @Test
    public void testDeniedAccessForTenant() throws Exception {
        mockMvc.perform(get("/api/deal-admin/chats")
                        .with(tenantAuth()))
                .andExpect(status().isForbidden());
    }
}
