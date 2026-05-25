package com.example.backend;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class BackendApplication {

    public static void main(String[] args) {
        SpringApplication.run(BackendApplication.class, args);
    }

    /**
     * Регистрируем JavaTimeModule, чтобы {@code LocalDateTime} в DTO
     * сериализовались в ISO-строки, а не «массив [yyyy, m, d, h, m, s]».
     * Используется в OverpassPersistentCache (snapshot JSON), в snapshot'ах
     * скоринга и в любых responseDTO с timestamp'ами.
     */
    @Bean
    public ObjectMapper objectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        mapper.registerModule(new JavaTimeModule());
        return mapper;
    }
}
