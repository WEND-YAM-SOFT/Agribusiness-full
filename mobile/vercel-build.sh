#!/usr/bin/env bash
set -euo pipefail

# Install Flutter on Vercel build image when unavailable.
if ! command -v flutter >/dev/null 2>&1; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version
flutter config --no-analytics
flutter pub get
flutter build web --release --dart-define=API_BASE_URL="${API_BASE_URL:-http://localhost:5000/api}"
