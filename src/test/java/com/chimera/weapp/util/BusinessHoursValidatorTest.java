package com.chimera.weapp.util;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class BusinessHoursValidatorTest {

    @Test
    public void testValidSingleSegment() {
        assertTrue(BusinessHoursValidator.isValid("08:00-22:00"));
        assertTrue(BusinessHoursValidator.isValid("00:00-23:59"));
        assertTrue(BusinessHoursValidator.isValid("07:30-11:30"));
    }

    @Test
    public void testValidMultiSegment() {
        assertTrue(BusinessHoursValidator.isValid("07:30-11:30,12:30-16:30,20:30-22:30"));
        assertTrue(BusinessHoursValidator.isValid("08:00-12:00,14:00-18:00"));
        assertTrue(BusinessHoursValidator.isValid("00:00-06:00,22:00-23:59"));
    }

    @Test
    public void testInvalidFormats() {
        // Empty/null
        assertFalse(BusinessHoursValidator.isValid(null));
        assertFalse(BusinessHoursValidator.isValid(""));
        assertFalse(BusinessHoursValidator.isValid("   "));

        // Wrong separator
        assertFalse(BusinessHoursValidator.isValid("08:00~22:00"));
        
        // Invalid time
        assertFalse(BusinessHoursValidator.isValid("25:00-22:00"));
        assertFalse(BusinessHoursValidator.isValid("08:00-24:00"));
        assertFalse(BusinessHoursValidator.isValid("8:00-22:00")); // Missing leading zero
        
        // Missing parts
        assertFalse(BusinessHoursValidator.isValid("08:00"));
        assertFalse(BusinessHoursValidator.isValid("-22:00"));
        assertFalse(BusinessHoursValidator.isValid("08:00-"));
    }

    @Test
    public void testValidationWithMessage() {
        // Valid cases return null
        assertNull(BusinessHoursValidator.validateWithMessage("08:00-22:00"));
        assertNull(BusinessHoursValidator.validateWithMessage("07:30-11:30,12:30-16:30"));

        // Invalid cases return error message
        assertNotNull(BusinessHoursValidator.validateWithMessage(null));
        assertNotNull(BusinessHoursValidator.validateWithMessage(""));
        assertNotNull(BusinessHoursValidator.validateWithMessage("25:00-22:00"));
        
        // Start time >= end time
        assertNotNull(BusinessHoursValidator.validateWithMessage("22:00-08:00"));
        assertNotNull(BusinessHoursValidator.validateWithMessage("08:00-08:00"));
        
        // Overlapping segments
        assertNotNull(BusinessHoursValidator.validateWithMessage("08:00-12:00,10:00-14:00"));
    }

    @Test
    public void testIsWithinBusinessHours() {
        // Single segment
        assertTrue(BusinessHoursValidator.isWithinBusinessHours("08:00-22:00", 12, 0));
        assertFalse(BusinessHoursValidator.isWithinBusinessHours("08:00-22:00", 23, 0));
        assertFalse(BusinessHoursValidator.isWithinBusinessHours("08:00-22:00", 7, 0));

        // Multi-segment
        assertTrue(BusinessHoursValidator.isWithinBusinessHours("07:30-11:30,12:30-16:30,20:30-22:30", 8, 0));   // First segment
        assertTrue(BusinessHoursValidator.isWithinBusinessHours("07:30-11:30,12:30-16:30,20:30-22:30", 14, 0));  // Second segment
        assertTrue(BusinessHoursValidator.isWithinBusinessHours("07:30-11:30,12:30-16:30,20:30-22:30", 21, 0));  // Third segment
        assertFalse(BusinessHoursValidator.isWithinBusinessHours("07:30-11:30,12:30-16:30,20:30-22:30", 12, 0)); // Gap between segments
    }

    @Test
    public void testFormatForDisplay() {
        assertEquals("08:00-22:00", BusinessHoursValidator.formatForDisplay("08:00-22:00"));
        assertEquals("07:30-11:30 | 12:30-16:30 | 20:30-22:30", 
                     BusinessHoursValidator.formatForDisplay("07:30-11:30,12:30-16:30,20:30-22:30"));
    }
}
