package com.chimera.weapp.controller;

import com.chimera.weapp.annotation.LoginRequired;
import com.chimera.weapp.entity.AppConfiguration;
import com.chimera.weapp.repository.AppConfigurationRepository;
import com.chimera.weapp.util.BusinessHoursValidator;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.bson.types.ObjectId;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.DayOfWeek;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.EnumSet;
import java.util.Set;
import java.util.List;

@RestController
@RequestMapping("/appConfiguration")
public class AppConfigurationController {
    @Autowired
    private AppConfigurationRepository repository;

    @GetMapping
    @LoginRequired
    @Operation(description = "获取所有配置")
    public ResponseEntity<List<AppConfiguration>> getAllAppConfigurations() {
        return ResponseEntity.ok(repository.findAll());
    }

    @PutMapping
    @LoginRequired
    @Operation(description = "对单个做修改")
    public ResponseEntity<?> updateConfiguration(@Valid @RequestBody AppConfiguration appConfiguration) {
        // Validate business hours format if updating business hours configurations
        String key = appConfiguration.getKey();
        if ("weekdays_opening_hours".equals(key) || "weekend_opening_hours".equals(key)) {
            String errorMessage = BusinessHoursValidator.validateWithMessage(appConfiguration.getValue());
            if (errorMessage != null) {
                return ResponseEntity.badRequest().body(new ErrorResponse(errorMessage));
            }
        }
        
        AppConfiguration save = repository.save(appConfiguration);
        return ResponseEntity.ok(save);
    }
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ErrorResponse {
        private String error;
    }

    @GetMapping("/openingTime")
    @Operation(description = "获取营业时间")
    public ResponseEntity<String> getOpeningTime() {
        // 默认使用系统时区
        ZoneId currentZone = ZoneId.systemDefault();
        ZonedDateTime now = ZonedDateTime.now(currentZone);
        DayOfWeek dayOfWeek = now.getDayOfWeek();

        // 根据区域设置不同的周末定义
        Set<DayOfWeek> weekendDays = EnumSet.of(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY);

        String openingTimeKey = weekendDays.contains(dayOfWeek) ? "weekend_opening_hours" : "weekdays_opening_hours";

        String openingTime = repository.findByKey(openingTimeKey)
                .map(AppConfiguration::getValue)
                .orElseThrow(() -> new RuntimeException("营业时间未找到"));

        return ResponseEntity.ok(openingTime);
    }
    
    @GetMapping("/openingTime/structured")
    @Operation(description = "获取营业时间的结构化数据，支持多段营业时间")
    public ResponseEntity<OpeningTimeResponse> getOpeningTimeStructured() {
        ZoneId currentZone = ZoneId.systemDefault();
        ZonedDateTime now = ZonedDateTime.now(currentZone);
        DayOfWeek dayOfWeek = now.getDayOfWeek();

        Set<DayOfWeek> weekendDays = EnumSet.of(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY);
        String openingTimeKey = weekendDays.contains(dayOfWeek) ? "weekend_opening_hours" : "weekdays_opening_hours";

        String openingTime = repository.findByKey(openingTimeKey)
                .map(AppConfiguration::getValue)
                .orElseThrow(() -> new RuntimeException("营业时间未找到"));

        // Parse multi-segment format
        List<TimeSegment> segments = parseTimeSegments(openingTime);
        
        return ResponseEntity.ok(new OpeningTimeResponse(openingTime, segments));
    }
    
    private List<TimeSegment> parseTimeSegments(String businessHours) {
        List<TimeSegment> segments = new java.util.ArrayList<>();
        if (businessHours == null || businessHours.trim().isEmpty()) {
            return segments;
        }
        
        String[] parts = businessHours.trim().split(",");
        for (String part : parts) {
            String[] times = part.split("-");
            if (times.length == 2) {
                segments.add(new TimeSegment(times[0].trim(), times[1].trim()));
            }
        }
        return segments;
    }
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class TimeSegment {
        private String start;
        private String end;
    }
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class OpeningTimeResponse {
        private String rawValue;
        private List<TimeSegment> segments;
    }

    @GetMapping("/timeToStopOrdering")
    @Operation(description = "定时达截至下单时间间隔，单位：分钟。")
    public ResponseEntity<String> getTimeToStopOrdering() {

        String openingTime = repository.findByKey("time_to_stop_ordering")
                .map(AppConfiguration::getValue)
                .orElseThrow(() -> new RuntimeException("未找到配置"));

        return ResponseEntity.ok(openingTime);
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class AppConfigurationApiParams {
        @Schema(description = "配置项的键名，例如 \"api.url\"")
        @NotNull
        private String key;
        @Schema(description = "配置项的值，例如 \"https://api.example.com\"")
        @NotNull
        private String value;
        @Schema(description = "配置项的描述")
        private String description;
        @Schema(description = "配置类别（用于分组管理）")
        private String category;
    }

    @PostMapping
    @LoginRequired
    @Operation(description = "新增一个")
    public ResponseEntity<?> addConfiguration(@Valid @RequestBody AppConfigurationApiParams apiParams) {
        // Validate business hours format if creating business hours configurations
        if ("weekdays_opening_hours".equals(apiParams.key) || "weekend_opening_hours".equals(apiParams.key)) {
            String errorMessage = BusinessHoursValidator.validateWithMessage(apiParams.value);
            if (errorMessage != null) {
                return ResponseEntity.badRequest().body(new ErrorResponse(errorMessage));
            }
        }
        
        AppConfiguration save = repository.save(AppConfiguration.builder()
                .key(apiParams.key)
                .value(apiParams.value)
                .description(apiParams.description)
                .category(apiParams.category).build());
        return ResponseEntity.ok(save);
    }

    @DeleteMapping("/{id}")
    @LoginRequired
    @Operation(description = "删除一个")
    public ResponseEntity<Void> deleteConfiguration(@PathVariable String id) {
        if (!ObjectId.isValid(id)) {
            return ResponseEntity.badRequest().build();
        }

        if (repository.existsById(new ObjectId(id))) {
            repository.deleteById(new ObjectId(id));
            return ResponseEntity.noContent().build(); // 204 No Content
        } else {
            return ResponseEntity.notFound().build(); // 404 Not Found
        }
    }
}
