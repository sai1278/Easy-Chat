.PHONY: all setup proto fmt lint test backend mobile docker up down clean ci help

# Setup system shell to bash for portability
SHELL := /usr/bin/env bash

# Define directories
BACKEND_DIR := apps/backend
FRONTEND_DIR := apps/frontend

# Default target
all: help

help:
	@echo "====================================================="
	@echo "Nearby Connect Monorepo Build Interface"
	@echo "====================================================="
	@echo "Available commands:"
	@echo "  make setup     - Validate environment dependencies and install protobuf plugins"
	@echo "  make proto     - Compile gRPC stubs from .proto definition schemas"
	@echo "  make fmt       - Format all code sources (Go & Dart)"
	@echo "  make lint      - Run code analysis and linter checks"
	@echo "  make test      - Run all unit and integration test suites"
	@echo "  make backend   - Compile all Go microservices binaries"
	@echo "  make mobile    - Run build command for Flutter app preview"
	@echo "  make docker    - Build all application docker container images"
	@echo "  make up        - Start local docker-compose environment in background"
	@echo "  make down      - Stop and remove local docker-compose environment containers"
	@echo "  make clean     - Remove compiled binaries, caches, and generated stubs"
	@echo "  make ci        - Run complete CI pipeline verification locally"

setup:
	@chmod +x scripts/setup_dev.sh
	./scripts/setup_dev.sh

proto:
	@chmod +x scripts/generate_proto.sh
	./scripts/generate_proto.sh

fmt:
	@echo "Formatting Go files..."
	cd $(BACKEND_DIR) && go fmt ./...
	@if command -v flutter &>/dev/null; then \
		echo "Formatting Dart files..."; \
		cd $(FRONTEND_DIR) && flutter format lib/; \
	fi

lint:
	@echo "Running Go static checks..."
	cd $(BACKEND_DIR) && go vet ./...
	@if command -v flutter &>/dev/null; then \
		echo "Running Flutter static analyze..."; \
		cd $(FRONTEND_DIR) && flutter analyze; \
	fi

test:
	@echo "Running Go unit tests..."
	cd $(BACKEND_DIR) && go test -v -race ./...
	@if command -v flutter &>/dev/null; then \
		echo "Running Flutter unit tests..."; \
		cd $(FRONTEND_DIR) && flutter test; \
	fi

backend: proto
	@echo "Compiling backend binaries..."
	mkdir -p $(BACKEND_DIR)/bin
	cd $(BACKEND_DIR)/services/auth && go build -o ../../bin/auth.exe ./cmd/auth/main.go
	cd $(BACKEND_DIR)/services/user && go build -o ../../bin/user.exe ./cmd/user/main.go
	cd $(BACKEND_DIR)/services/chat && go build -o ../../bin/chat.exe ./cmd/chat/main.go
	cd $(BACKEND_DIR)/services/nearby && go build -o ../../bin/nearby.exe ./cmd/nearby/main.go
	cd $(BACKEND_DIR)/services/presence && go build -o ../../bin/presence.exe ./cmd/presence/main.go
	cd $(BACKEND_DIR)/services/notification && go build -o ../../bin/notification.exe ./cmd/notification/main.go
	cd $(BACKEND_DIR)/services/media && go build -o ../../bin/media.exe ./cmd/media/main.go
	cd $(BACKEND_DIR)/services/gateway && go build -o ../../bin/gateway.exe ./cmd/gateway/main.go

mobile: proto
	@if command -v flutter &>/dev/null; then \
		echo "Compiling Flutter client build..."; \
		cd $(FRONTEND_DIR) && flutter build web --no-pub; \
	else \
		echo "⚠️ Warning: 'flutter' command not available. Skipping Flutter compilation."; \
	fi

docker:
	@echo "Building application containers..."
	docker compose build

up:
	@echo "Starting backend local environment..."
	docker compose up -d

down:
	@echo "Tearing down backend local environment..."
	docker compose down --remove-orphans

clean:
	@echo "Cleaning workspace targets..."
	rm -rf $(BACKEND_DIR)/bin/
	rm -rf $(BACKEND_DIR)/internal/gen/
	rm -rf $(FRONTEND_DIR)/lib/gen/
	rm -rf $(FRONTEND_DIR)/build/
	rm -rf $(FRONTEND_DIR)/.dart_tool/

ci: setup proto fmt lint test
	@echo "====================================================="
	@echo "🎉 CI Validation check completed successfully."
	@echo "====================================================="
