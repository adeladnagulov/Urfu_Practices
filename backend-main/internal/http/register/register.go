package register

import (
	"Urfu_Practices/internal/http/health"
	"Urfu_Practices/internal/http/middleware"
	"log/slog"

	"github.com/go-chi/chi/v5"
)

func RegisterRoutes(r chi.Router,
	logger *slog.Logger,
	healthHandler *health.Handler,
) {
	r.Use(middleware.Recover(logger))
	r.Use(middleware.Logging(logger))

	r.Get("/health", healthHandler.Health)
	r.Get("/ready", healthHandler.Ready)

	r.Route("/api/v1", func(r chi.Router) {
	})
}
