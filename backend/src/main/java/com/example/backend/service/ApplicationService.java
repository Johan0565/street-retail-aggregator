package com.example.backend.service;

import com.example.backend.dto.ApplicationResponseDto;
import com.example.backend.entity.*;
import com.example.backend.entity.enums.ApplicationStatus;
import com.example.backend.entity.enums.PropertyStatus;
import com.example.backend.entity.enums.Role;
import com.example.backend.repository.ApplicationRepository;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ApplicationService {

    private final ApplicationRepository applicationRepository;
    private final PropertyRepository propertyRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    @Transactional
    public ApplicationResponseDto createApplication(Long tenantId, Long propertyId, String coverLetter) {
        User tenant = userRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        if (property.getStatus() != PropertyStatus.PUBLISHED) {
            throw new RuntimeException("Помещение недоступно для аренды");
        }

        Application application = Application.builder()
                .tenant(tenant)
                .property(property)
                .status(ApplicationStatus.PENDING)
                .coverLetter(coverLetter)
                .build();

        Application saved = applicationRepository.save(application);
        notificationService.sendPushNotification(property.getLandlord().getId(), "Новая заявка", "Поступила новая заявка на помещение: " + property.getTitle());
        return mapToDto(saved);
    }

    @Transactional
    public ApplicationResponseDto updateApplicationStatus(Long landlordId, Long applicationId, ApplicationStatus newStatus) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new RuntimeException("Заявка не найдена"));

        // Важная проверка безопасности: принадлежит ли помещение этому арендодателю?
        if (!application.getProperty().getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("У вас нет прав на изменение этой заявки");
        }

        application.setStatus(newStatus);

        // Если заявка принята, можно сразу поменять статус помещения на RENTED
        if (newStatus == ApplicationStatus.ACCEPTED) {
            Property property = application.getProperty();
            property.setStatus(PropertyStatus.RENTED);
            propertyRepository.save(property);
        }

        Application saved = applicationRepository.save(application);
        notificationService.sendPushNotification(application.getTenant().getId(), "Статус заявки обновлен", "Ваша заявка перешла в статус: " + newStatus);
        return mapToDto(saved);
    }

    @Transactional(readOnly = true)
    public List<ApplicationResponseDto> getTenantApplications(Long tenantId) {
        return applicationRepository.findByTenantId(tenantId).stream()
                .map(this::mapToDto)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ApplicationResponseDto> getLandlordApplications(Long landlordId) {
        return applicationRepository.findByProperty_LandlordId(landlordId).stream()
                .map(this::mapToDto)
                .collect(Collectors.toList());
    }

    @Transactional
    public void deleteApplication(Long tenantId, Long applicationId) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new RuntimeException("Заявка не найдена"));

        if (!application.getTenant().getId().equals(tenantId)) {
            throw new RuntimeException("Вы не можете удалить чужую заявку");
        }

        // Если заявка уже принята, удалять нельзя
        if (application.getStatus() == ApplicationStatus.ACCEPTED) {
            throw new RuntimeException("Нельзя удалить уже принятую заявку");
        }

        applicationRepository.delete(application);
    }

    @Transactional(readOnly = true)
    public ApplicationResponseDto getApplicationById(Long applicationId, Long currentUserId, Role currentUserRole) {
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new RuntimeException("Заявка не найдена"));

        // Проверка безопасности: арендатор может смотреть только свои заявки, арендодатель - только на свои помещения
        if (currentUserRole == Role.TENANT && !application.getTenant().getId().equals(currentUserId)) {
            throw new RuntimeException("Доступ запрещен. Это не ваша заявка.");
        }
        if (currentUserRole == Role.LANDLORD && !application.getProperty().getLandlord().getId().equals(currentUserId)) {
            throw new RuntimeException("Доступ запрещен. Это заявка не на ваше помещение.");
        }

        return mapToDto(application);
    }
    @Transactional
    public ApplicationResponseDto updateApplicationStatus(Long landlordId, Long applicationId, ApplicationStatus newStatus, String rejectionReason) { // <-- Добавили String rejectionReason
        Application application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new RuntimeException("Заявка не найдена"));

        // Важная проверка безопасности: принадлежит ли помещение этому арендодателю?
        if (!application.getProperty().getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("У вас нет прав на изменение этой заявки");
        }

        application.setStatus(newStatus);

        // --- СОХРАНЯЕМ ПРИЧИНУ ОТКАЗА ---
        if (newStatus == ApplicationStatus.REJECTED && rejectionReason != null) {
            application.setRejectionReason(rejectionReason);
        }

        // Если заявка принята, можно сразу поменять статус помещения на RENTED
        if (newStatus == ApplicationStatus.ACCEPTED) {
            Property property = application.getProperty();
            property.setStatus(PropertyStatus.RENTED);
            propertyRepository.save(property);
        }

        Application saved = applicationRepository.save(application);
        notificationService.sendPushNotification(application.getTenant().getId(), "Статус заявки обновлен", "Ваша заявка перешла в статус: " + newStatus);
        return mapToDto(saved);
    }
    // Вспомогательный метод маппинга Entity -> DTO
    private ApplicationResponseDto mapToDto(Application app) {
        String tenantName = "Не указано";
        String tenantPhone = "Не указано";

        if (app.getTenant().getTenantProfile() != null) {
            tenantName = app.getTenant().getTenantProfile().getName();
            tenantPhone = app.getTenant().getTenantProfile().getPhone();
        }

        return ApplicationResponseDto.builder()
                .id(app.getId())
                .status(app.getStatus())
                .coverLetter(app.getCoverLetter())
                .createdAt(app.getCreatedAt())
                .rejectionReason(app.getRejectionReason())
                .property(ApplicationResponseDto.PropertyShortInfo.builder()
                        .id(app.getProperty().getId())
                        .title(app.getProperty().getTitle())
                        .address(app.getProperty().getAddress())
                        .build())
                .tenant(ApplicationResponseDto.TenantShortInfo.builder()
                        .id(app.getTenant().getId())
                        .email(app.getTenant().getEmail())
                        .name(tenantName)
                        .phone(tenantPhone)
                        .build())
                .build();
    }
}