package container

import (
	"Urfu_Practices/internal/config"
	"Urfu_Practices/internal/http/health"
	"Urfu_Practices/internal/http/register"
	"Urfu_Practices/internal/infra/postgres"
	txManager "Urfu_Practices/internal/infra/postgres/transaction"
	"Urfu_Practices/internal/infra/telemetry"
	"context"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Container struct {
	srv *http.Server
	db  *postgres.DB
}

func New(cfg *config.Config) (*Container, error) {
	connectCtx, cancel := context.WithTimeout(context.Background(), cfg.DatabaseConnectTimeout)
	defer cancel()

	logger := telemetry.NewLogger(config.ParseLodLevel(cfg.LogLevel))

	db, err := postgres.NewDB(connectCtx, cfg)
	if err != nil {
		logger.ErrorContext(connectCtx, "connect DB error",
			slog.String("error", err.Error()),
		)
		return nil, fmt.Errorf("failed to load storage: %v", err)
	}

	_ = txManager.NewTransactionManager(db.Pool, cfg.DatabaseQueryTimeout)

	healthH := health.NewHandler(db.Pool)

	r := chi.NewRouter()
	register.RegisterRoutes(r, healthH)
	srv := &http.Server{
		Addr:              cfg.HttpAddr,
		Handler:           r,
		ReadTimeout:       cfg.HttpReadTimeout,
		ReadHeaderTimeout: cfg.HttpReadHeaderTimeout,
		WriteTimeout:      cfg.HttpWriteTimeout,
		IdleTimeout:       cfg.HttpIdleTimeout,
	}

	return &Container{srv: srv, db: db}, nil
}
