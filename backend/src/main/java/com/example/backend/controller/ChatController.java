package com.example.backend.controller;

import com.example.backend.dto.ChatMessageDto;
import com.example.backend.dto.ChatRoomDto;
import com.example.backend.dto.SendMessageRequest;
import com.example.backend.entity.User;
import com.example.backend.service.ChatService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;

@RestController
@RequestMapping("/api/chat")
@RequiredArgsConstructor
public class ChatController {

    private final ChatService chatService;
    private final SimpMessagingTemplate messagingTemplate;

    @GetMapping("/applications/{applicationId}/room")
    public ResponseEntity<ChatRoomDto> getOrCreateRoom(@PathVariable Long applicationId) {
        return ResponseEntity.ok(chatService.getOrCreateChatRoom(applicationId));
    }

    @GetMapping("/rooms")
    public ResponseEntity<List<ChatRoomDto>> getMyRooms(Principal principal) {
        return ResponseEntity.ok(chatService.getUserChatRooms(extractUserIdFromPrincipal(principal)));
    }

    @GetMapping("/rooms/{roomId}/messages")
    public ResponseEntity<List<ChatMessageDto>> getMessages(@PathVariable Long roomId) {
        return ResponseEntity.ok(chatService.getChatMessages(roomId));
    }

    @PostMapping("/rooms/{roomId}/messages")
    public ResponseEntity<ChatMessageDto> sendMessage(
            @PathVariable Long roomId,
            @RequestBody SendMessageRequest request,
            Principal principal) {
        
        Long userId = extractUserIdFromPrincipal(principal);
        ChatMessageDto message = chatService.saveMessage(roomId, userId, request.getContent());
        
        // Broadcast to WebSocket subscribers
        messagingTemplate.convertAndSend("/topic/chat/" + roomId, message);
        
        return ResponseEntity.ok(message);
    }

    private Long extractUserIdFromPrincipal(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken authToken) {
            User user = (User) authToken.getPrincipal();
            return user.getId();
        }
        throw new RuntimeException("Unauthorized");
    }
}
