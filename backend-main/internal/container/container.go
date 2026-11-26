package container

import (
	"Urfu_Practices/internal/config"
	"Urfu_Practices/internal/infra/telemetry"
	"context"
)

type Container struct {
}

func New(cfg *config.Config) (*Container, error) {
	connectCtx, cancel := context.WithTimeout(context.Background(), cfg.DatabaseConnectTimeout)
	defer cancel()

	logger := telemetry.NewLogger(config.ParseLodLevel(cfg.LogLevel))
	return &Container{}, nil
}
