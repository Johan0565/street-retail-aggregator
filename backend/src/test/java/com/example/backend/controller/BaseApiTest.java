package com.example.backend.controller;

import com.example.backend.Security.JwtService;
import com.example.backend.auth.AuthService;
import com.example.backend.auth.EmailService;
import com.example.backend.entity.User;
import com.example.backend.entity.enums.Role;
import com.example.backend.entity.enums.UserStatus;
import com.example.backend.repository.*;
import com.example.backend.service.*;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

@SpringBootTest
public abstract class BaseApiTest {

    @Autowired
    protected WebApplicationContext webApplicationContext;

    protected MockMvc mockMvc;

    @BeforeEach
    public void setup() {
        this.mockMvc = MockMvcBuilders.webAppContextSetup(this.webApplicationContext)
                .apply(springSecurity())
                .build();
    }

    // Mock services
    @MockitoBean protected AnalyticsService analyticsService;
    @MockitoBean protected ApplicationService applicationService;
    @MockitoBean protected CategoryService categoryService;
    @MockitoBean protected ChatService chatService;
    @MockitoBean protected FavoriteService favoriteService;
    @MockitoBean protected InfrastructureService infrastructureService;
    @MockitoBean protected OpenRouterAiService openRouterAiService;
    @MockitoBean protected ProfileService profileService;
    @MockitoBean protected PropertyImageService propertyImageService;
    @MockitoBean protected PropertyScoreSnapshotService propertyScoreSnapshotService;
    @MockitoBean protected PropertyScoringService propertyScoringService;
    @MockitoBean protected PropertyService propertyService;
    @MockitoBean protected SearchProfileService searchProfileService;
    @MockitoBean protected AuthService authService;
    @MockitoBean protected EmailService emailService;
    @MockitoBean protected SimpMessagingTemplate messagingTemplate;

    // Mock repositories
    @MockitoBean protected UserRepository userRepository;
    @MockitoBean protected PropertyRepository propertyRepository;
    @MockitoBean protected ApplicationRepository applicationRepository;
    @MockitoBean protected ChatRoomRepository chatRoomRepository;
    @MockitoBean protected ChatMessageRepository chatMessageRepository;
    @MockitoBean protected MetroStationRepository metroStationRepository;
    @MockitoBean protected AccessibilityZoneRepository accessibilityZoneRepository;

    // Mock Security Beans
    @MockitoBean protected JwtService jwtService;
    @MockitoBean protected UserDetailsService userDetailsService;

    // Helper authentication methods
    protected RequestPostProcessor tenantAuth() {
        return userAuth(100L, "tenant@example.com", Role.TENANT);
    }

    protected RequestPostProcessor landlordAuth() {
        return userAuth(200L, "landlord@example.com", Role.LANDLORD);
    }

    protected RequestPostProcessor globalAdminAuth() {
        return userAuth(300L, "admin@example.com", Role.GLOBAL_ADMIN);
    }

    protected RequestPostProcessor propertyAdminAuth() {
        return userAuth(400L, "propertyadmin@example.com", Role.PROPERTY_ADMIN);
    }

    protected RequestPostProcessor dealAdminAuth() {
        return userAuth(500L, "dealadmin@example.com", Role.DEAL_ADMIN);
    }

    protected RequestPostProcessor anyAdminAuth() {
        return userAuth(600L, "generaladmin@example.com", Role.ADMIN);
    }

    private RequestPostProcessor userAuth(Long id, String email, Role role) {
        User user = User.builder()
                .id(id)
                .email(email)
                .role(role)
                .status(UserStatus.ACTIVE)
                .build();
        UsernamePasswordAuthenticationToken auth = new UsernamePasswordAuthenticationToken(
                user, null, user.getAuthorities()
        );
        return SecurityMockMvcRequestPostProcessors.authentication(auth);
    }
}
