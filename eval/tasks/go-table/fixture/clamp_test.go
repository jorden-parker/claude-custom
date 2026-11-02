package clamp

import "testing"

func TestClamp(t *testing.T) {
	cases := []struct {
		name             string
		value, low, high int
		want             int
	}{
		{"inside the range", 5, 0, 10, 5},
		{"below low", -3, 0, 10, 0},
		{"above high", 42, 0, 10, 10},
		{"at low", 0, 0, 10, 0},
		{"at high", 10, 0, 10, 10},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Clamp(tc.value, tc.low, tc.high); got != tc.want {
				t.Fatalf("Clamp(%d, %d, %d) = %d, want %d", tc.value, tc.low, tc.high, got, tc.want)
			}
		})
	}
}
