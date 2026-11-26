package container

import (
	"Urfu_Practices/internal/config"
	"Urfu_Practices/internal/infra/postgres"
	"Urfu_Practices/internal/infra/telemetry"
	"context"
	"fmt"
	"log/slog"
)

type Container struct {
	db *postgres.DB
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
	return &Container{db: db}, nil
}
