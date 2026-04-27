package com.example.backend.repository;
import com.example.backend.entity.BusinessCategory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public interface BusinessCategoryRepository extends JpaRepository<BusinessCategory, Long> {
    List<BusinessCategory> findByParentCategoryIsNull();
}