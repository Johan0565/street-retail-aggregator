package com.example.backend.dto;

import com.example.backend.entity.enums.Role;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;


@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class RegisterRequest {
    private String email;
    private String password;
    private Role role; // TENANT или LANDLORD

    private String name; // ФИО/Название
    private String inn;
    private String phone;
}
