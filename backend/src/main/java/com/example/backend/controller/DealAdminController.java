package com.example.backend.controller;

import com.example.backend.dto.ChatMessageDto;
import com.example.backend.dto.SendMessageRequest;
import com.example.backend.dto.TransactionReportDto;
import com.example.backend.entity.*;
import com.example.backend.entity.enums.ApplicationStatus;
import com.example.backend.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/deal-admin")
@RequiredArgsConstructor
@PreAuthorize("hasAnyRole('ADMIN', 'DEAL_ADMIN')")
public class DealAdminController {

    private final ChatRoomRepository chatRoomRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final ApplicationRepository applicationRepository;
    private final UserRepository userRepository;
    private final SimpMessagingTemplate messagingTemplate;

    // --- Chat & Disputes Management ---

    @GetMapping("/chats")
    public ResponseEntity<List<ChatRoom>> getAllChats() {
        return ResponseEntity.ok(chatRoomRepository.findAll());
    }

    @GetMapping("/chats/{roomId}/messages")
    public ResponseEntity<List<ChatMessageDto>> getChatMessages(@PathVariable Long roomId) {
        List<ChatMessageDto> messages = chatMessageRepository.findByChatRoomIdOrderByTimestampAsc(roomId)
                .stream()
                .map(msg -> ChatMessageDto.builder()
                        .id(msg.getId())
                        .chatRoomId(msg.getChatRoom().getId())
                        .senderId(msg.getSender().getId())
                        .senderName(msg.getSender().getEmail())
                        .content(msg.getContent())
                        .isRead(msg.isRead())
                        .timestamp(msg.getTimestamp())
                        .build())
                .collect(Collectors.toList());
        return ResponseEntity.ok(messages);
    }

    @PostMapping("/chats/{roomId}/messages")
    public ResponseEntity<ChatMessageDto> sendModeratorMessage(
            @PathVariable Long roomId,
            @RequestBody SendMessageRequest request,
            Principal principal) {
        
        ChatRoom chatRoom = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new RuntimeException("Chat room not found"));
        
        User moderator = (User) ((UsernamePasswordAuthenticationToken) principal).getPrincipal();

        ChatMessage message = ChatMessage.builder()
                .chatRoom(chatRoom)
                .sender(moderator)
                .content("[Модератор " + moderator.getEmail() + "]: " + request.getContent())
                .isRead(false)
                .build();

        ChatMessage saved = chatMessageRepository.save(message);

        ChatMessageDto dto = ChatMessageDto.builder()
                .id(saved.getId())
                .chatRoomId(saved.getChatRoom().getId())
                .senderId(saved.getSender().getId())
                .senderName(saved.getSender().getEmail())
                .content(saved.getContent())
                .isRead(saved.isRead())
                .timestamp(saved.getTimestamp())
                .build();

        // Broadcast to websocket
        messagingTemplate.convertAndSend("/topic/chat/" + roomId, dto);

        return ResponseEntity.ok(dto);
    }

    @PostMapping("/chats/{roomId}/dispute")
    public ResponseEntity<ChatRoom> openDispute(@PathVariable Long roomId, @RequestParam String notes) {
        ChatRoom chatRoom = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new RuntimeException("Chat room not found"));
        chatRoom.setIsDisputed(true);
        chatRoom.setDisputeResolved(false);
        chatRoom.setDisputeNotes(notes);
        return ResponseEntity.ok(chatRoomRepository.save(chatRoom));
    }

    @PatchMapping("/chats/{roomId}/resolve-dispute")
    public ResponseEntity<ChatRoom> resolveDispute(@PathVariable Long roomId) {
        ChatRoom chatRoom = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new RuntimeException("Chat room not found"));
        chatRoom.setDisputeResolved(true);
        chatRoom.setIsDisputed(false);
        return ResponseEntity.ok(chatRoomRepository.save(chatRoom));
    }

    // --- Deal Applications Moderation ---

    @PostMapping("/applications/{applicationId}/confirm-deal")
    public ResponseEntity<Application> confirmLeaseDeal(@PathVariable Long applicationId) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new RuntimeException("Lease application not found"));
        
        if (application.getStatus() != ApplicationStatus.ACCEPTED) {
            throw new RuntimeException("Можно подтвердить только принятые арендодателем заявки");
        }

        application.setIsDealConfirmed(true);
        application.setDealConfirmedAt(LocalDateTime.now());
        return ResponseEntity.ok(applicationRepository.save(application));
    }

    // --- Transaction Reports ---

    @GetMapping("/transactions/report")
    public ResponseEntity<List<TransactionReportDto>> getTransactionReport() {
        List<TransactionReportDto> report = getConcludedDealsReport();
        return ResponseEntity.ok(report);
    }

    @GetMapping("/transactions/report/csv")
    public ResponseEntity<byte[]> downloadTransactionReportCsv() {
        List<TransactionReportDto> report = getConcludedDealsReport();
        
        StringBuilder csv = new StringBuilder();
        // UTF-8 BOM for proper Excel encoding display
        csv.append('\ufeff');
        csv.append("ID Заявки,ID Помещения,Название,Адрес,Email Арендатора,Имя Арендатора,Email Арендодателя,Компания Арендодателя,Арендная плата (₽/мес),Дата подтверждения сделки\n");

        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

        for (TransactionReportDto dto : report) {
            csv.append(dto.getApplicationId()).append(",")
               .append(dto.getPropertyId()).append(",")
               .append("\"").append(escapeCsv(dto.getPropertyTitle())).append("\",")
               .append("\"").append(escapeCsv(dto.getPropertyAddress())).append("\",")
               .append(dto.getTenantEmail()).append(",")
               .append("\"").append(escapeCsv(dto.getTenantName())).append("\",")
               .append(dto.getLandlordEmail()).append(",")
               .append("\"").append(escapeCsv(dto.getLandlordCompanyName())).append("\",")
               .append(dto.getPricePerMonth()).append(",")
               .append(dto.getDealConfirmedAt() != null ? dto.getDealConfirmedAt().format(formatter) : "").append("\n");
        }

        byte[] output = csv.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
        headers.setContentDispositionFormData("attachment", "commercial_transactions_report.csv");
        headers.setContentLength(output.length);

        return new ResponseEntity<>(output, headers, HttpStatus.OK);
    }

    private List<TransactionReportDto> getConcludedDealsReport() {
        return applicationRepository.findAll().stream()
                .filter(a -> a.getStatus() == ApplicationStatus.ACCEPTED && Boolean.TRUE.equals(a.getIsDealConfirmed()))
                .map(a -> {
                    String tenantName = a.getTenant().getTenantProfile() != null ? a.getTenant().getTenantProfile().getName() : "N/A";
                    String landlordCompany = a.getProperty().getLandlord().getLandlordProfile() != null ? a.getProperty().getLandlord().getLandlordProfile().getCompanyName() : "N/A";
                    return TransactionReportDto.builder()
                            .applicationId(a.getId())
                            .propertyId(a.getProperty().getId())
                            .propertyTitle(a.getProperty().getTitle())
                            .propertyAddress(a.getProperty().getAddress())
                            .tenantEmail(a.getTenant().getEmail())
                            .tenantName(tenantName)
                            .landlordEmail(a.getProperty().getLandlord().getEmail())
                            .landlordCompanyName(landlordCompany)
                            .pricePerMonth(a.getProperty().getPricePerMonth())
                            .dealConfirmedAt(a.getDealConfirmedAt())
                            .build();
                })
                .collect(Collectors.toList());
    }

    private String escapeCsv(String value) {
        if (value == null) return "";
        return value.replace("\"", "\"\"");
    }
}
