#!/usr/bin/env bash
# Builds linux/dist/minisnap_<version>_all.deb (Ubuntu 24.04+). Pure Python, so one package fits every architecture.
set -euo pipefail

cd "$(dirname "$0")/.."            # linux/
VERSION="$(python3 -c 'import re; print(re.search(r"VERSION\s*=\s*\"([^\"]+)\"", open("minisnap/__init__.py", encoding="utf-8").read()).group(1))')"
PKG="build/minisnap_${VERSION}_all"
APP_ID="io.github.kingrubic.MiniSnap"

rm -rf build dist
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/minisnap" "$PKG/usr/share/applications" \
         "$PKG/usr/share/icons/hicolor/scalable/apps" "$PKG/usr/share/metainfo" "$PKG/usr/share/doc/minisnap" dist

echo "==> Copying the application ($VERSION)"
cp -r minisnap "$PKG/usr/share/minisnap/"
find "$PKG" -name '__pycache__' -type d -prune -exec rm -rf {} +
install -m 755 bin/minisnap "$PKG/usr/bin/minisnap"
install -m 644 "data/$APP_ID.desktop" "$PKG/usr/share/applications/"
install -m 644 "data/icons/hicolor/scalable/apps/$APP_ID.svg" "$PKG/usr/share/icons/hicolor/scalable/apps/"
install -m 644 "data/$APP_ID.metainfo.xml" "$PKG/usr/share/metainfo/"
install -m 644 ../LICENSE "$PKG/usr/share/doc/minisnap/copyright"

INSTALLED_KB="$(du -sk "$PKG/usr" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<EOF
Package: minisnap
Version: $VERSION
Section: graphics
Priority: optional
Architecture: all
Installed-Size: $INSTALLED_KB
Depends: python3 (>= 3.10), python3-gi, python3-gi-cairo, python3-cairo, gir1.2-gtk-4.0, gir1.2-adw-1, gir1.2-gstreamer-1.0, gir1.2-gst-plugins-base-1.0, gstreamer1.0-pipewire, gstreamer1.0-plugins-good, xdg-desktop-portal
Recommends: tesseract-ocr, tesseract-ocr-vie, tesseract-ocr-eng, gstreamer1.0-plugins-ugly, xdg-desktop-portal-gnome | xdg-desktop-portal-kde | xdg-desktop-portal-gtk
Maintainer: Nguyễn Năng Quốc Bảo <nnqbao@gmail.com>
Homepage: https://github.com/nnqbao/minisnap
Description: Free, open-source screen capture and screen recording tool
 MiniSnap captures a region, a window or the whole screen, lets you
 annotate it (arrows, boxes, text, blur, step numbers), records the
 screen to video, extracts text with OCR and keeps a library of your
 captures. English and Vietnamese user interface.
EOF

# Refresh the icon cache and desktop database when installed (both are optional on the system).
cat > "$PKG/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v gtk4-update-icon-cache >/dev/null 2>&1 && gtk4-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
exit 0
EOF
cp "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"
chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

echo "==> Building the package"
dpkg-deb --build --root-owner-group "$PKG" dist/
ls -la dist
dpkg-deb --info dist/*.deb
