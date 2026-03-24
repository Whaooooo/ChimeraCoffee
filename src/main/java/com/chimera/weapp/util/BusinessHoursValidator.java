package com.chimera.weapp.util;

import java.util.regex.Pattern;

/**
 * Utility class for validating business hours format.
 * Supports both single segment: "08:00-22:00"
 * and multi-segment: "07:30-11:30,12:30-16:30,20:30-22:30"
 */
public class BusinessHoursValidator {
    
    // Pattern for HH:mm format (00:00 to 23:59)
    private static final String TIME_PATTERN = "([01]\\d|2[0-3]):([0-5]\\d)";
    
    // Pattern for a single time segment (e.g., "08:00-22:00")
    private static final String SEGMENT_PATTERN = TIME_PATTERN + "-" + TIME_PATTERN;
    
    // Pattern for multiple segments separated by commas
    private static final Pattern MULTI_SEGMENT_PATTERN = Pattern.compile(
        "^" + SEGMENT_PATTERN + "(," + SEGMENT_PATTERN + ")*$"
    );
    
    /**
     * Validates if the given business hours string is in valid format.
     * 
     * @param businessHours the business hours string to validate
     * @return true if valid, false otherwise
     */
    public static boolean isValid(String businessHours) {
        if (businessHours == null || businessHours.trim().isEmpty()) {
            return false;
        }
        
        return MULTI_SEGMENT_PATTERN.matcher(businessHours.trim()).matches();
    }
    
    /**
     * Validates and returns error message if invalid.
     * 
     * @param businessHours the business hours string to validate
     * @return null if valid, error message if invalid
     */
    public static String validateWithMessage(String businessHours) {
        if (businessHours == null || businessHours.trim().isEmpty()) {
            return "营业时间不能为空";
        }
        
        if (!MULTI_SEGMENT_PATTERN.matcher(businessHours.trim()).matches()) {
            return "营业时间格式无效，正确格式如：\"08:00-22:00\" 或 \"07:30-11:30,12:30-16:30,20:30-22:30\"";
        }
        
        // Validate that each segment's start time is before end time
        String[] segments = businessHours.trim().split(",");
        for (String segment : segments) {
            String[] times = segment.split("-");
            if (times.length != 2) {
                return "时间段格式错误：" + segment;
            }
            
            int startMinutes = parseTimeToMinutes(times[0]);
            int endMinutes = parseTimeToMinutes(times[1]);
            
            if (startMinutes >= endMinutes) {
                return "开始时间必须早于结束时间：" + segment;
            }
        }
        
        // Validate no overlapping segments
        if (segments.length > 1) {
            int[][] timeRanges = new int[segments.length][2];
            for (int i = 0; i < segments.length; i++) {
                String[] times = segments[i].split("-");
                timeRanges[i][0] = parseTimeToMinutes(times[0]);
                timeRanges[i][1] = parseTimeToMinutes(times[1]);
            }
            
            // Check for overlaps
            for (int i = 0; i < timeRanges.length; i++) {
                for (int j = i + 1; j < timeRanges.length; j++) {
                    if (timeRangesOverlap(timeRanges[i][0], timeRanges[i][1], 
                                          timeRanges[j][0], timeRanges[j][1])) {
                        return "时间段不能重叠：" + segments[i] + " 与 " + segments[j];
                    }
                }
            }
        }
        
        return null; // Valid
    }
    
    /**
     * Parses time string (HH:mm) to minutes since midnight.
     */
    private static int parseTimeToMinutes(String time) {
        String[] parts = time.split(":");
        int hours = Integer.parseInt(parts[0]);
        int minutes = Integer.parseInt(parts[1]);
        return hours * 60 + minutes;
    }
    
    /**
     * Checks if two time ranges overlap.
     */
    private static boolean timeRangesOverlap(int start1, int end1, int start2, int end2) {
        return start1 < end2 && start2 < end1;
    }
    
    /**
     * Checks if current time is within business hours.
     * 
     * @param businessHours the business hours string
     * @param currentHour current hour (0-23)
     * @param currentMinute current minute (0-59)
     * @return true if within business hours
     */
    public static boolean isWithinBusinessHours(String businessHours, int currentHour, int currentMinute) {
        if (!isValid(businessHours)) {
            return false;
        }
        
        int currentMinutes = currentHour * 60 + currentMinute;
        String[] segments = businessHours.trim().split(",");
        
        for (String segment : segments) {
            String[] times = segment.split("-");
            int startMinutes = parseTimeToMinutes(times[0]);
            int endMinutes = parseTimeToMinutes(times[1]);
            
            if (currentMinutes >= startMinutes && currentMinutes < endMinutes) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Formats business hours for display.
     * 
     * @param businessHours the raw business hours string
     * @return formatted string for display
     */
    public static String formatForDisplay(String businessHours) {
        if (!isValid(businessHours)) {
            return businessHours;
        }
        
        String[] segments = businessHours.trim().split(",");
        if (segments.length == 1) {
            return segments[0];
        }
        
        return String.join(" | ", segments);
    }
}
