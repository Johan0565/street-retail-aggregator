package com.example.backend.service;

import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.*;
import java.util.Set;
import java.util.UUID;

@Slf4j
@Service
public class FileStorageService {

    private static final Set<String> ALLOWED_MIME = Set.of(
            "image/jpeg", "image/jpg", "image/png", "image/webp"
    );
    private static final long MAX_BYTES = 5L * 1024 * 1024; // 5MB

    @Value("${app.upload.dir:./uploads}")
    private String uploadDir;

    private Path root;

    @PostConstruct
    public void init() {
        this.root = Paths.get(uploadDir).toAbsolutePath().normalize();
        try {
            Files.createDirectories(root);
        } catch (IOException e) {
            throw new IllegalStateException("Не удалось создать директорию для файлов: " + root, e);
        }
        log.info("File storage root: {}", root);
    }

    /**
     * Сохраняет файл в подкаталог и возвращает относительный URL вида /uploads/{subdir}/{filename}.
     */
    public String store(MultipartFile file, String subdir) {
        validate(file);
        try {
            Path dir = root.resolve(subdir).normalize();
            if (!dir.startsWith(root)) {
                throw new IllegalArgumentException("Некорректный путь");
            }
            Files.createDirectories(dir);

            String ext = resolveExtension(file.getContentType(), file.getOriginalFilename());
            String name = UUID.randomUUID() + ext;
            Path target = dir.resolve(name);
            Files.copy(file.getInputStream(), target, StandardCopyOption.REPLACE_EXISTING);
            return "/uploads/" + subdir + "/" + name;
        } catch (IOException e) {
            throw new RuntimeException("Не удалось сохранить файл", e);
        }
    }

    /**
     * Удаляет файл по URL вида /uploads/.... Молча игнорирует, если файла нет.
     */
    public void delete(String publicUrl) {
        if (publicUrl == null || !publicUrl.startsWith("/uploads/")) return;
        try {
            String relative = publicUrl.substring("/uploads/".length());
            Path target = root.resolve(relative).normalize();
            if (target.startsWith(root)) {
                Files.deleteIfExists(target);
            }
        } catch (IOException e) {
            log.warn("Не удалось удалить файл {}: {}", publicUrl, e.getMessage());
        }
    }

    public Path getRoot() {
        return root;
    }

    private void validate(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("Файл пустой");
        }
        if (file.getSize() > MAX_BYTES) {
            throw new IllegalArgumentException("Файл больше 5MB");
        }
        String mime = file.getContentType();
        if (mime == null || !ALLOWED_MIME.contains(mime.toLowerCase())) {
            throw new IllegalArgumentException("Поддерживаются только JPEG/PNG/WebP");
        }
    }

    private String resolveExtension(String mime, String originalName) {
        if (mime != null) {
            switch (mime.toLowerCase()) {
                case "image/jpeg":
                case "image/jpg": return ".jpg";
                case "image/png": return ".png";
                case "image/webp": return ".webp";
            }
        }
        if (originalName != null) {
            int dot = originalName.lastIndexOf('.');
            if (dot >= 0) return originalName.substring(dot).toLowerCase();
        }
        return "";
    }
}
