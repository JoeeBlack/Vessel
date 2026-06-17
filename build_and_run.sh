#!/bin/bash

# Zatrzymanie skryptu w przypadku wystąpienia błędu
set -e

echo "======================================"
echo "🚢 Budowanie projektu Vessel (macOS)..."
echo "======================================"

# Kompilacja projektu Swift pod kątem lokalnej architektury
swift build

# Pobranie ścieżki do wygenerowanych plików binarnych
BIN_PATH=$(swift build --show-bin-path)

echo "🔐 Podpisywanie binarne z uprawnieniami (entitlements)..."
codesign --force --options runtime --sign - --entitlements Vessel.entitlements "$BIN_PATH/Vessel"

echo ""
echo "======================================"
echo "🚀 Uruchamianie aplikacji Vessel..."
echo "======================================"

# Uruchomienie wygenerowanego pliku binarnego
"$BIN_PATH/Vessel"
