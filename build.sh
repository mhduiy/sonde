#!/usr/bin/env bash
# Sonde 一键构建（开发用）
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 1/2 构建 Rust 核心 (sondecore)"
(cd rustcore && cargo build --release)

echo "==> 2/2 构建 Qt 前端 (sonde)"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build

echo
echo "完成：$(pwd)/build/sonde"
echo "试运行： ./build/sonde --bus session"
