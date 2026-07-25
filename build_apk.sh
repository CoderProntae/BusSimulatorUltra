#!/bin/bash
# Build script for Bus Simulator Ultra - Godot 4 Android APK
# Requires: Godot 4.4+ with Android export templates, Android SDK, OpenJDK 17+

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_PRESET="Android (Release)"
BUILD_DIR="$PROJECT_DIR/build"
APK_PATH="$BUILD_DIR/BusSimulatorUltra.apk"

echo "=========================================="
echo "Bus Simulator Ultra - APK Build Script"
echo "=========================================="

# Check for Godot binary
GODOT_BINARY=""
if command -v godot &> /dev/null; then
    GODOT_BINARY=$(command -v godot)
elif [ -f "/usr/bin/godot" ]; then
    GODOT_BINARY="/usr/bin/godot"
elif [ -f "/usr/local/bin/godot" ]; then
    GODOT_BINARY="/usr/local/bin/godot"
elif [ -f "$HOME/bin/godot" ]; then
    GODOT_BINARY="$HOME/bin/godot"
fi

if [ -n "$GODOT_BINARY" ]; then
    echo "✓ Godot found: $GODOT_BINARY"
    $GODOT_BINARY --version
else
    echo "✗ Godot binary not found in PATH."
    echo "  Please install Godot 4.4+ binary and add to PATH."
    echo "  Download from: https://godotengine.org/download"
    echo ""
fi

# Check for Android SDK
ANDROID_HOME=""
if [ -n "$ANDROID_HOME" ]; then
    echo "✓ ANDROID_HOME set: $ANDROID_HOME"
elif [ -n "$ANDROID_SDK_ROOT" ]; then
    echo "✓ ANDROID_SDK_ROOT set: $ANDROID_SDK_ROOT"
    ANDROID_HOME="$ANDROID_SDK_ROOT"
else
    echo "✗ Android SDK not configured."
    echo "  Set ANDROID_HOME to your Android SDK path."
fi

# Check for Java
if command -v java &> /dev/null; then
    echo "✓ Java found: $(java -version 2>&1 | head -1)"
else
    echo "✗ Java not found. OpenJDK 17+ is required."
fi

# Check for export templates
if [ -f "$HOME/.local/share/godot/export_templates/4.4.stable/custom.py" ]; then
    echo "✓ Godot export templates found (4.4.stable)"
elif [ -f "/usr/share/godot/export_templates/4.4.stable/custom.py" ]; then
    echo "✓ Godot export templates found (system)"
else
    echo "✗ Godot Android export templates not found."
    echo "  In Godot: Editor -> Manage Export Templates -> Install Android Template"
fi

mkdir -p "$BUILD_DIR"

# Try to build with Godot if available
if [ -n "$GODOT_BINARY" ] && [ -n "$ANDROID_HOME" ] && command -v java &> /dev/null; then
    echo ""
    echo "Starting APK export..."
    echo "Project: $PROJECT_DIR"
    echo "Preset: $EXPORT_PRESET"
    echo ""
    
    $GODOT_BINARY --headless --export-release "$EXPORT_PRESET" "$APK_PATH" 2>&1 | tee "$BUILD_DIR/export.log"
    
    if [ -f "$APK_PATH" ]; then
        APK_SIZE=$(ls -lh "$APK_PATH" | awk '{print $5}')
        echo ""
        echo "✓ APK built successfully!"
        echo "  Size: $APK_SIZE"
        echo "  Path: $APK_PATH"
        
        # Generate SHA256 for verification
        sha256sum "$APK_PATH" > "$BUILD_DIR/BusSimulatorUltra.apk.sha256"
        echo "  SHA256: $(cat '$BUILD_DIR/BusSimulatorUltra.apk.sha256')"
        
        exit 0
    else
        echo ""
        echo "✗ APK export failed. See $BUILD_DIR/export.log for details."
        exit 1
    fi
else
    echo ""
    echo "=========================================="
    echo "Build prerequisites missing."
    echo "=========================================="
    echo "To build the APK, you need:"
    echo "  1. Godot 4.4+ binary (https://godotengine.org/download)"
    echo "  2. Android SDK (https://developer.android.com/studio)"
    echo "  3. OpenJDK 17+ (apt install openjdk-17-jdk)"
    echo "  4. Godot Android export templates"
    echo ""
    echo "Once installed, run: $0"
    echo ""
    echo "Project is fully configured at: $PROJECT_DIR"
    echo "Main scene: res://scenes/main_scene.tscn"
    echo ""
fi
