package domainerror

import (
	"Urfu_Practices/internal/http/helper/decode"
	"Urfu_Practices/internal/http/models"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
)

func Problem(err error, r *http.Request) (int, models.Problem) {
	if err == nil {
		return http.StatusOK, models.Problem{}
	}
	host := getRoutePattern(r)
	typeConflict := "about:blank"
	switch {
	case isValidationError(err):
		detail := "invalid request body or parameters"
		return http.StatusBadRequest, models.Problem{
			Type:     typeConflict,
			Title:    http.StatusText(http.StatusBadRequest),
			Status:   http.StatusBadRequest,
			Detail:   &detail,
			Code:     "invalid_request",
			Instance: &host,
		}
	default:
		detail := "internal server error"
		return http.StatusInternalServerError, models.Problem{
			Type:     typeConflict,
			Title:    http.StatusText(http.StatusInternalServerError),
			Status:   http.StatusInternalServerError,
			Detail:   &detail,
			Code:     "internal_error",
			Instance: &host,
		}
	}
}

func isValidationError(err error) bool {
	if err == nil {
		return false
	}
	var validateErr *decode.ValidationErr
	return errors.As(err, &validateErr)
}

func getRoutePattern(r *http.Request) string {
	if routeCtx := chi.RouteContext(r.Context()); routeCtx != nil {
		return routeCtx.RoutePattern()
	}
	return r.URL.Path
}
