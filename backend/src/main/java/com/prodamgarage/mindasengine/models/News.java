package com.prodamgarage.mindasengine.models;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;

@Entity
@Table(name = "news")
@Data
@NoArgsConstructor
@RequiredArgsConstructor
public class News {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @NonNull
    @Column(length = 500)
    private String name;
    // Без columnDefinition Hibernate делает varchar(255), и описание длиннее
    // 255 символов роняло вставку: SQLState 22001, "value too long".
    @NonNull
    @Column(columnDefinition = "text")
    private String description;
    @NonNull
    @Column(columnDefinition = "DATE")
    private LocalDate publication;
}
