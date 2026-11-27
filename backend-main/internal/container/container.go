package container

import (
	"Urfu_Practices/internal/config"
	"Urfu_Practices/internal/http/health"
	"Urfu_Practices/internal/http/register"
	"Urfu_Practices/internal/infra/postgres"
	txManager "Urfu_Practices/internal/infra/postgres/transaction"
	"Urfu_Practices/internal/infra/telemetry"
	"context"
	"errors"
	"fmt"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/go-chi/chi/v5"
)

type Container struct {
	srv *http.Server
	db  *postgres.DB
	cfg *config.Config
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

	healthH := health.NewHandler(db)

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

	return &Container{srv: srv, db: db, cfg: cfg}, nil
}

func (c *Container) Run() {
	srvErrCh := make(chan error, 1)
	go func() {
		log.Printf("Starting server on %s", c.srv.Addr)
		if err := c.srv.ListenAndServe(); err != nil {
			srvErrCh <- err
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case <-quit:
		log.Println("shutting down gracefully")
	case err := <-srvErrCh:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Printf("server failed to start or crashed: %v", err)
		}
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), c.cfg.ShutdownTimeout)
	defer cancel()

	if err := c.srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}
	c.db.Close()
	log.Println("Server exited gracefully")
}
