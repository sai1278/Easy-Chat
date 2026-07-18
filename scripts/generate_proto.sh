#!/usr/bin/env bash
# generate_proto.sh - Generates Go and Dart gRPC stubs from .proto schemas.
set -euo pipefail

# Find workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Verify tool dependencies
if ! command -v protoc &>/dev/null; then
    echo "❌ Error: 'protoc' not found." >&2
    exit 1
fi

if ! command -v protoc-gen-go &>/dev/null; then
    echo "❌ Error: 'protoc-gen-go' plugin not found. Please run 'make setup' first." >&2
    exit 1
fi

if ! command -v protoc-gen-go-grpc &>/dev/null; then
    echo "❌ Error: 'protoc-gen-go-grpc' plugin not found. Please run 'make setup' first." >&2
    exit 1
fi

# Locate protoc-gen-dart. Usually dart pub downloads it to ~/.pub-cache/bin.
if ! command -v protoc-gen-dart &>/dev/null; then
    # Fallback checks for common dart cache locations to help dev UX
    DART_CACHE_BIN="${HOME}/.pub-cache/bin"
    if [ -d "${DART_CACHE_BIN}" ] && [ -x "${DART_CACHE_BIN}/protoc-gen-dart" ]; then
        export PATH="${DART_CACHE_BIN}:${PATH}"
    elif [ -n "${APPDATA:-}" ] && [ -d "${APPDATA}/Pub/Cache/bin" ]; then
        export PATH="${APPDATA}/Pub/Cache/bin:${PATH}"
    elif [ -d "${HOME}/.pub-cache/bin" ]; then
        export PATH="${HOME}/.pub-cache/bin:${PATH}"
    else
        echo "⚠️ Warning: 'protoc-gen-dart' not found in typical caches. Executing with system PATH." >&2
    fi
fi

# Define generation outputs
GO_GEN_DIR="${WORKSPACE_ROOT}/apps/backend/internal/gen"
DART_GEN_DIR="${WORKSPACE_ROOT}/apps/frontend/lib/gen"

# Ensure clean state in output directories
rm -rf "${GO_GEN_DIR}"
rm -rf "${DART_GEN_DIR}"
mkdir -p "${GO_GEN_DIR}"
mkdir -p "${DART_GEN_DIR}"

echo "Compiling Protobuf schemas..."

# Compile Go stubs
echo "➡️ Generating Go stubs -> apps/backend/internal/gen/"
protoc \
  --proto_path="${WORKSPACE_ROOT}/proto" \
  --go_out="${GO_GEN_DIR}" \
  --go_opt=module=nearby/backend/internal/gen \
  --go-grpc_out="${GO_GEN_DIR}" \
  --go-grpc_opt=module=nearby/backend/internal/gen \
  "${WORKSPACE_ROOT}"/proto/nearby/v1/*.proto

# Compile Dart stubs
echo "➡️ Generating Dart stubs -> apps/frontend/lib/gen/"
protoc \
  --proto_path="${WORKSPACE_ROOT}/proto" \
  --dart_out="grpc:${DART_GEN_DIR}" \
  "${WORKSPACE_ROOT}"/proto/nearby/v1/*.proto

echo "✅ Protobuf code generation completed successfully."
