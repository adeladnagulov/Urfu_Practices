package register

import (
	"Urfu_Practices/internal/http/health"

	"github.com/go-chi/chi/v5"
)

func RegisterRoutes(r chi.Router,
	healthHandler *health.Handler,
) {
	//middleware

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/health", healthHandler.Health)
		r.Get("/ready", healthHandler.Ready)
	})
}
