package main

import (
	"strings"
	"testing"
)

func TestCalculateHealthScorePerfect(t *testing.T) {
	score, msg := calculateHealthScore(
		CPUStatus{Usage: 10},
		MemoryStatus{UsedPercent: 20, Pressure: "normal"},
		[]DiskStatus{{UsedPercent: 30}},
		DiskIOStatus{ReadRate: 5, WriteRate: 5},
		ThermalStatus{CPUTemp: 40},
	)

	if score != 100 {
		t.Fatalf("expected perfect score 100, got %d", score)
	}
	if msg != "Excellent" {
		t.Fatalf("unexpected message %q", msg)
	}
}

func TestCalculateHealthScoreDetectsIssues(t *testing.T) {
	score, msg := calculateHealthScore(
		CPUStatus{Usage: 95},
		MemoryStatus{UsedPercent: 90, Pressure: "critical"},
		[]DiskStatus{{UsedPercent: 95}},
		DiskIOStatus{ReadRate: 120, WriteRate: 80},
		ThermalStatus{CPUTemp: 90},
	)

	if score >= 40 {
		t.Fatalf("expected heavy penalties bringing score down, got %d", score)
	}
	if msg == "Excellent" {
		t.Fatalf("expected message to include issues, got %q", msg)
	}
	if !strings.Contains(msg, "High CPU") {
		t.Fatalf("message should mention CPU issue: %q", msg)
	}
	if !strings.Contains(msg, "Disk Almost Full") {
		t.Fatalf("message should mention disk issue: %q", msg)
	}
}

func TestFormatUptime(t *testing.T) {
	if got := formatUptime(65); got != "1m" {
		t.Fatalf("expected 1m, got %s", got)
	}
	if got := formatUptime(3600 + 120); got != "1h 2m" {
		t.Fatalf("expected \"1h 2m\", got %s", got)
	}
	if got := formatUptime(86400*2 + 3600*3 + 60*5); got != "2d 3h 5m" {
		t.Fatalf("expected \"2d 3h 5m\", got %s", got)
	}
}

func TestColorizeTempThresholds(t *testing.T) {
	tests := []struct {
		temp     float64
		expected string
	}{
		{temp: 30.0, expected: "30.0"},  // Normal - should use okStyle (green)
		{temp: 55.9, expected: "55.9"},  // Just below warning threshold
		{temp: 56.0, expected: "56.0"},  // Warning threshold - should use warnStyle (yellow)
		{temp: 65.0, expected: "65.0"},  // Mid warning range
		{temp: 75.9, expected: "75.9"},  // Just below danger threshold
		{temp: 76.0, expected: "76.0"},  // Danger threshold - should use dangerStyle (red)
		{temp: 90.0, expected: "90.0"},  // High temperature
		{temp: 0.0, expected: "0.0"},    // Edge case: zero
	}

	for _, tt := range tests {
		result := colorizeTemp(tt.temp)
		// Check that result contains the formatted temperature value
		if !strings.Contains(result, tt.expected) {
			t.Errorf("colorizeTemp(%.1f) = %q, should contain %q", tt.temp, result, tt.expected)
		}
		// Verify output is not empty and contains the temperature
		if result == "" {
			t.Errorf("colorizeTemp(%.1f) returned empty string", tt.temp)
		}
	}
}

func TestColorizeTempStyleRanges(t *testing.T) {
	// Test that different temperature ranges use different styles
	// We can't easily test the exact style applied, but we can verify
	// the function returns consistent results for each range

	normalTemp := colorizeTemp(40.0)
	warningTemp := colorizeTemp(65.0)
	dangerTemp := colorizeTemp(85.0)

	// All should be non-empty and contain the formatted value
	if normalTemp == "" || warningTemp == "" || dangerTemp == "" {
		t.Fatal("colorizeTemp should not return empty strings")
	}

	// Verify formatting precision (one decimal place)
	if !strings.Contains(normalTemp, "40.0") {
		t.Errorf("normal temp should contain '40.0', got: %s", normalTemp)
	}
	if !strings.Contains(warningTemp, "65.0") {
		t.Errorf("warning temp should contain '65.0', got: %s", warningTemp)
	}
	if !strings.Contains(dangerTemp, "85.0") {
		t.Errorf("danger temp should contain '85.0', got: %s", dangerTemp)
	}
}
