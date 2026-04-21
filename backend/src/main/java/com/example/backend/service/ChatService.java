package com.example.backend.service;

import com.example.backend.dto.ChatMessageDto;
import com.example.backend.dto.ChatRoomDto;
import com.example.backend.entity.Application;
import com.example.backend.entity.ChatMessage;
import com.example.backend.entity.ChatRoom;
import com.example.backend.entity.User;
import com.example.backend.repository.ApplicationRepository;
import com.example.backend.repository.ChatMessageRepository;
import com.example.backend.repository.ChatRoomRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ChatService {

    private final ChatRoomRepository chatRoomRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final ApplicationRepository applicationRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    @Transactional
    public ChatRoomDto getOrCreateChatRoom(Long applicationId) {
        ChatRoom chatRoom = chatRoomRepository.findByApplicationId(applicationId)
                .orElseGet(() -> createChatRoom(applicationId));
        return mapToChatRoomDto(chatRoom);
    }

    private ChatRoom createChatRoom(Long applicationId) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new RuntimeException("Application not found"));

        ChatRoom chatRoom = ChatRoom.builder()
                .application(application)
                .landlord(application.getProperty().getLandlord())
                .tenant(application.getTenant())
                .build();
        return chatRoomRepository.save(chatRoom);
    }

    public List<ChatRoomDto> getUserChatRooms(Long userId) {
        return chatRoomRepository.findByLandlordIdOrTenantId(userId, userId)
                .stream()
                .map(this::mapToChatRoomDto)
                .collect(Collectors.toList());
    }

    public List<ChatMessageDto> getChatMessages(Long roomId) {
        return chatMessageRepository.findByChatRoomIdOrderByTimestampAsc(roomId)
                .stream()
                .map(this::mapToChatMessageDto)
                .collect(Collectors.toList());
    }

    @Transactional
    public ChatMessageDto saveMessage(Long roomId, Long senderId, String content) {
        ChatRoom chatRoom = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new RuntimeException("Chat room not found"));
        User sender = userRepository.findById(senderId)
                .orElseThrow(() -> new RuntimeException("Sender not found"));

        ChatMessage message = ChatMessage.builder()
                .chatRoom(chatRoom)
                .sender(sender)
                .content(content)
                .isRead(false)
                .build();

        ChatMessage savedMessage = chatMessageRepository.save(message);
        
        Long recipientId = chatRoom.getLandlord().getId().equals(senderId) 
                ? chatRoom.getTenant().getId() 
                : chatRoom.getLandlord().getId();
        notificationService.sendPushNotification(recipientId, "Новое сообщение", "От " + sender.getEmail() + ": " + content);

        return mapToChatMessageDto(savedMessage);
    }

    private ChatRoomDto mapToChatRoomDto(ChatRoom chatRoom) {
        return ChatRoomDto.builder()
                .id(chatRoom.getId())
                .applicationId(chatRoom.getApplication().getId())
                .landlordId(chatRoom.getLandlord().getId())
                .landlordName(chatRoom.getLandlord().getEmail())
                .tenantId(chatRoom.getTenant().getId())
                .tenantName(chatRoom.getTenant().getEmail())
                .build();
    }

    private ChatMessageDto mapToChatMessageDto(ChatMessage message) {
        return ChatMessageDto.builder()
                .id(message.getId())
                .chatRoomId(message.getChatRoom().getId())
                .senderId(message.getSender().getId())
                .senderName(message.getSender().getEmail())
                .content(message.getContent())
                .isRead(message.isRead())
                .timestamp(message.getTimestamp())
                .build();
    }
}
