package models

// Defines values for HealthResponseStatus.
const (
	Ok          HealthResponseStatus = "ok"
	Unavailable HealthResponseStatus = "unavailable"
)

// HealthResponse defines model for HealthResponse.
type HealthResponse struct {
	Status HealthResponseStatus `json:"status"`
}

// HealthResponseStatus defines model for HealthResponse.Status.
type HealthResponseStatus string

// Problem Problem Details for HTTP APIs (RFC 9457) с дополнительным полем code.
type Problem struct {
	Code     string  `json:"code"`
	Detail   *string `json:"detail,omitempty"`
	Instance *string `json:"instance,omitempty"`
	Status   int32   `json:"status"`
	Title    string  `json:"title"`
	Type     string  `json:"type"`
}
