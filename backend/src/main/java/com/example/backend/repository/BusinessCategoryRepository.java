package com.example.backend.repository;
import com.example.backend.entity.BusinessCategory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
public interface BusinessCategoryRepository extends JpaRepository<BusinessCategory, Long> {
    List<BusinessCategory> findByParentCategoryIsNull();
    Optional<BusinessCategory> findByName(String name);
}