#!/bin/bash
cd "$(dirname "$0")/example"
flutter clean
flutter pub get
cd ..
flutter analyze
#git diff
