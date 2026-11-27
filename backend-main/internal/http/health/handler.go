package health

import (
	domainerror "Urfu_Practices/internal/http/domaineror"
	"Urfu_Practices/internal/http/helper/response"
	"Urfu_Practices/internal/http/models"
	"context"
	"net/http"
)

type DbPinger interface {
	PingDb(ctx context.Context) error
}

type Handler struct {
	db DbPinger
}

func NewHandler(db DbPinger) *Handler {
	return &Handler{
		db: db,
	}
}

// (GET /health)
func (h *Handler) Health(w http.ResponseWriter, _ *http.Request) {
	resp := models.HealthResponse{
		Status: models.Ok,
	}
	response.Json(w, http.StatusOK, resp)
}

// (GET /ready)
func (h *Handler) Ready(w http.ResponseWriter, r *http.Request) {
	if err := h.db.PingDb(r.Context()); err != nil {
		status, problem := domainerror.Problem(err, r)
		response.Problem(w, status, problem)
		return
	}
	resp := models.HealthResponse{
		Status: models.Ok,
	}
	response.Json(w, http.StatusOK, resp)
}
