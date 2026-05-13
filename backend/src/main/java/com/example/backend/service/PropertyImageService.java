package com.example.backend.service;

import com.example.backend.entity.Property;
import com.example.backend.entity.PropertyImage;
import com.example.backend.repository.PropertyImageRepository;
import com.example.backend.repository.PropertyRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class PropertyImageService {

    private static final int MAX_IMAGES_PER_PROPERTY = 10;

    private final PropertyRepository propertyRepository;
    private final PropertyImageRepository imageRepository;
    private final FileStorageService fileStorageService;

    @Transactional
    public List<PropertyImage> upload(Long landlordId, Long propertyId, List<MultipartFile> files) {
        Property property = loadOwned(landlordId, propertyId);

        List<PropertyImage> existing = imageRepository.findByPropertyId(propertyId);
        if (existing.size() + files.size() > MAX_IMAGES_PER_PROPERTY) {
            throw new IllegalArgumentException(
                    "Превышен лимит фотографий (" + MAX_IMAGES_PER_PROPERTY + ")");
        }

        boolean hasMain = existing.stream().anyMatch(i -> Boolean.TRUE.equals(i.getIsMain()));

        List<PropertyImage> saved = new ArrayList<>();
        for (MultipartFile file : files) {
            String url = fileStorageService.store(file, "properties/" + propertyId);
            PropertyImage image = PropertyImage.builder()
                    .property(property)
                    .imageUrl(url)
                    .isMain(!hasMain && saved.isEmpty())
                    .build();
            saved.add(imageRepository.save(image));
            if (Boolean.TRUE.equals(image.getIsMain())) {
                hasMain = true;
            }
        }
        return saved;
    }

    @Transactional
    public void delete(Long landlordId, Long propertyId, Long imageId) {
        loadOwned(landlordId, propertyId);
        PropertyImage image = imageRepository.findById(imageId)
                .orElseThrow(() -> new RuntimeException("Фото не найдено"));
        if (!image.getProperty().getId().equals(propertyId)) {
            throw new RuntimeException("Фото принадлежит другому объекту");
        }

        boolean wasMain = Boolean.TRUE.equals(image.getIsMain());
        fileStorageService.delete(image.getImageUrl());
        imageRepository.delete(image);

        if (wasMain) {
            imageRepository.findByPropertyId(propertyId).stream().findFirst().ifPresent(next -> {
                next.setIsMain(true);
                imageRepository.save(next);
            });
        }
    }

    @Transactional
    public void setMain(Long landlordId, Long propertyId, Long imageId) {
        loadOwned(landlordId, propertyId);
        List<PropertyImage> images = imageRepository.findByPropertyId(propertyId);
        boolean found = false;
        for (PropertyImage image : images) {
            boolean shouldBeMain = image.getId().equals(imageId);
            if (shouldBeMain) found = true;
            image.setIsMain(shouldBeMain);
        }
        if (!found) {
            throw new RuntimeException("Фото не найдено");
        }
        imageRepository.saveAll(images);
    }

    private Property loadOwned(Long landlordId, Long propertyId) {
        Property property = propertyRepository.findById(propertyId)
                .orElseThrow(() -> new RuntimeException("Помещение не найдено"));
        if (!property.getLandlord().getId().equals(landlordId)) {
            throw new RuntimeException("Нет прав на редактирование чужого объекта");
        }
        return property;
    }
}
