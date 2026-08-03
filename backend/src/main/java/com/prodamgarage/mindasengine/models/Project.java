package com.prodamgarage.mindasengine.models;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "project")
@Data
@NoArgsConstructor
@RequiredArgsConstructor
public class Project {
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
}
