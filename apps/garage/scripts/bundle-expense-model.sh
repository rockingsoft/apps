#!/bin/sh
set -eu

model_name=qwen2.5-1.5b-instruct-q4_k_m.gguf
expected_sha256=6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e
model_path="$PROJECT_DIR/build/$model_name"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/$model_name"

if [ ! -f "$model_path" ]; then
  mkdir -p "$(dirname "$model_path")"
  temporary_path="$model_path.partial"
  rm -f "$temporary_path"
  curl --fail --location --retry 3 --output "$temporary_path" \
    "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/$model_name"
  mv "$temporary_path" "$model_path"
fi

actual_sha256=$(shasum -a 256 "$model_path" | cut -d ' ' -f 1)
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "El modelo de IA no coincide con el SHA-256 esperado: $model_path" >&2
  rm -f "$model_path"
  exit 1
fi

mkdir -p "$(dirname "$destination")"
cp "$model_path" "$destination"
