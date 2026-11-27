package response

import (
	domainerror "Urfu_Practices/internal/http/domaineror"
	"Urfu_Practices/internal/http/models"
	"encoding/json"
	"net/http"
)

func Json(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func Problem(w http.ResponseWriter, status int, problem models.Problem) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(problem)
}

func HandleAPIError(w http.ResponseWriter, r *http.Request, err error) {
	status, problem := domainerror.Problem(err, r)
	Problem(w, status, problem)
}
