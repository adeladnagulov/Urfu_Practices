package main

import (
	"Urfu_Practices/internal/config"
	"Urfu_Practices/internal/container"
	"log"
)

func main() {
	cfg, err := config.NewConfig()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	container, err := container.New(cfg)
	if err != nil {
		log.Fatalf("failed to build container: %v", err)
	}

	container.Run()
}
