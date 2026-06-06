package com.example.backend.controller;

import com.example.backend.entity.User;
import com.example.backend.entity.enums.UserStatus;
import com.example.backend.repository.ApplicationRepository;
import com.example.backend.repository.PropertyRepository;
import com.example.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;

@RestController
@RequestMapping("/api/global-admin")
@RequiredArgsConstructor
@PreAuthorize("hasAnyRole('ADMIN', 'GLOBAL_ADMIN')")
public class GlobalAdminController {

    private final UserRepository userRepository;
    private final PropertyRepository propertyRepository;
    private final ApplicationRepository applicationRepository;

    @GetMapping("/users")
    public ResponseEntity<List<User>> getAllUsers() {
        return ResponseEntity.ok(userRepository.findAll());
    }

    @PostMapping("/users/{userId}/block")
    public ResponseEntity<User> blockUser(@PathVariable Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));
        user.setStatus(UserStatus.BANNED);
        return ResponseEntity.ok(userRepository.save(user));
    }

    @PostMapping("/users/{userId}/unblock")
    public ResponseEntity<User> unblockUser(@PathVariable Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));
        user.setStatus(UserStatus.ACTIVE);
        return ResponseEntity.ok(userRepository.save(user));
    }

    @GetMapping("/statistics")
    public ResponseEntity<Map<String, Object>> getAggregatorStatistics() {
        Map<String, Object> stats = new LinkedHashMap<>();

        // User stats
        List<User> users = userRepository.findAll();
        long tenantCount = users.stream().filter(u -> u.getRole() == com.example.backend.entity.enums.Role.TENANT).count();
        long landlordCount = users.stream().filter(u -> u.getRole() == com.example.backend.entity.enums.Role.LANDLORD).count();
        long adminCount = users.stream().filter(u -> u.getRole() == com.example.backend.entity.enums.Role.ADMIN 
                || u.getRole() == com.example.backend.entity.enums.Role.GLOBAL_ADMIN).count();
        long activeUsers = users.stream().filter(u -> u.getStatus() == UserStatus.ACTIVE).count();
        long bannedUsers = users.stream().filter(u -> u.getStatus() == UserStatus.BANNED).count();

        stats.put("totalUsers", users.size());
        stats.put("tenantsCount", tenantCount);
        stats.put("landlordsCount", landlordCount);
        stats.put("adminsCount", adminCount);
        stats.put("activeUsersCount", activeUsers);
        stats.put("bannedUsersCount", bannedUsers);

        // Property stats
        long totalProperties = propertyRepository.count();
        long publishedCount = propertyRepository.findAll().stream().filter(p -> p.getStatus() == com.example.backend.entity.enums.PropertyStatus.PUBLISHED).count();
        long rentedCount = propertyRepository.findAll().stream().filter(p -> p.getStatus() == com.example.backend.entity.enums.PropertyStatus.RENTED).count();

        stats.put("totalProperties", totalProperties);
        stats.put("publishedProperties", publishedCount);
        stats.put("rentedProperties", rentedCount);

        // Deal / Application stats
        long totalApplications = applicationRepository.count();
        long acceptedDeals = applicationRepository.findAll().stream().filter(a -> a.getStatus() == com.example.backend.entity.enums.ApplicationStatus.ACCEPTED).count();

        stats.put("totalApplications", totalApplications);
        stats.put("concludedDealsCount", acceptedDeals);

        return ResponseEntity.ok(stats);
    }

    @GetMapping("/logs")
    public ResponseEntity<List<String>> getLogs(@RequestParam(defaultValue = "100") int lines, @RequestParam(defaultValue = "stdout") String type) {
        int maxLines = Math.min(Math.max(1, lines), 1000);
        String logFileName = type.equals("stderr") ? "stderr.log" : "stdout.log";
        
        // Попробуем разные пути к лог-файлам
        Path logPath = Paths.get("logs", logFileName);
        if (!Files.exists(logPath)) {
            logPath = Paths.get("backend", "logs", logFileName);
        }
        if (!Files.exists(logPath)) {
            logPath = Paths.get("../logs", logFileName);
        }

        return ResponseEntity.ok(tailFile(logPath, maxLines));
    }

    private List<String> tailFile(Path path, int maxLines) {
        if (!Files.exists(path)) {
            return List.of("Log file not found at " + path.toAbsolutePath());
        }
        List<String> result = new ArrayList<>();
        try (RandomAccessFile fileHandler = new RandomAccessFile(path.toFile(), "r")) {
            long fileLength = fileHandler.length() - 1;
            StringBuilder sb = new StringBuilder();
            int lineCount = 0;

            // Читаем с конца файла побайтово
            for (long filePointer = fileLength; filePointer >= 0; filePointer--) {
                fileHandler.seek(filePointer);
                int readByte = fileHandler.readByte();

                if (readByte == 0xA) { // '\n'
                    if (filePointer == fileLength) {
                        continue;
                    }
                    result.add(0, new String(sb.reverse().toString().getBytes(StandardCharsets.ISO_8859_1), StandardCharsets.UTF_8));
                    sb.setLength(0);
                    lineCount++;
                    if (lineCount >= maxLines) {
                        break;
                    }
                } else if (readByte == 0xD) { // '\r'
                    // Игнорируем
                } else {
                    sb.append((char) readByte);
                }
            }
            if (sb.length() > 0 && lineCount < maxLines) {
                result.add(0, new String(sb.reverse().toString().getBytes(StandardCharsets.ISO_8859_1), StandardCharsets.UTF_8));
            }
        } catch (IOException e) {
            return List.of("Error reading logs: " + e.getMessage());
        }
        return result;
    }
}
