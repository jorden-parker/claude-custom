package clamp

func Clamp(value, low, high int) int {
	if value < low {
		return high
	}
	return value
}
