package com.example.backend.service;

import com.example.backend.entity.Property;
import com.example.backend.entity.User;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class FavoriteService {

    private final UserRepository userRepository;
    private final PropertyRepository propertyRepository;

    @Transactional
    public void addFavorite(Long tenantId, Long propertyId) {
        User user = userRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        // Добавляем помещение в Set. Благодаря @ManyToMany Hibernate сам обновит таблицу favorites
        user.getFavoriteProperties().add(property);
        userRepository.save(user);
    }

    @Transactional
    public void removeFavorite(Long tenantId, Long propertyId) {
        User user = userRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Пользователь не найден"));

        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));

        user.getFavoriteProperties().remove(property);
        userRepository.save(user);
    }

    @Transactional(readOnly = true)
    public List<Property> getFavorites(Long tenantId) {
        // Используем наш оптимизированный запрос
        return propertyRepository.findFavoritePropertiesByTenantId(tenantId);
    }
}