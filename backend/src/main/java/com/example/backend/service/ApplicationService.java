package com.example.backend.service;

import com.example.backend.entity.*;
import com.example.backend.repository.ApplicationRepository;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class ApplicationService {

    private final ApplicationRepository applicationRepository;
    private final PropertyRepository propertyRepository;
    private final UserRepository userRepository;


    @Transactional
    public Application createApplication(Long tenantId, Long propertyId, String coverLetter) {
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

        return applicationRepository.save(application);
    }


    @Transactional
    public Application updateApplicationStatus(Long landlordId, Long applicationId, ApplicationStatus newStatus) {
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

        return applicationRepository.save(application);
    }

    @Transactional(readOnly = true)
    public List<Application> getTenantApplications(Long tenantId) {
        return applicationRepository.findByTenantId(tenantId);
    }


    @Transactional(readOnly = true)
    public List<Application> getLandlordApplications(Long landlordId) {
        return applicationRepository.findByProperty_LandlordId(landlordId);
    }
}