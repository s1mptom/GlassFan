#!/bin/bash
# Prints the notes for a release: what to download and how to open it.
#   release-notes.sh <version> <notarised: true|false>
set -euo pipefail
VERSION="$1"
NOTARISED="${2:-false}"

cat <<EOF
## Download

**[GlassFan-$VERSION.dmg](https://github.com/s1mptom/GlassFan/releases/download/v$VERSION/GlassFan-$VERSION.dmg)** — open it and drag GlassFan to Applications.

Requires **macOS 26 or newer on Apple silicon**. Measured on a MacBook Pro with M1 Max and one with M3 Pro; the M1 Pro MacBook Pros share the M1 Max's layout. On any other chip the sensors are named from the machine's own key layout rather than from a table. On a MacBook Air (no fan) it shows temperatures only.

To control the fans, open **Settings → Fan control → Install**. macOS asks for your password once; the helper then starts with the system.
EOF

if [[ "$NOTARISED" != "true" ]]; then
cat <<'EOF'

### Opening it the first time

This build is not notarised by Apple, so macOS stops it on first launch with *"Apple could not verify GlassFan is free of malware"*. To open it anyway:

1. Try to open GlassFan once and close the message.
2. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to GlassFan.
3. Confirm with your password. From then on it opens normally.

Or, in Terminal, after moving the app to Applications:

```sh
xattr -dr com.apple.quarantine /Applications/GlassFan.app
```

<details>
<summary>По-русски</summary>

Сборка не нотаризована Apple, поэтому при первом запуске macOS её остановит. Откройте приложение один раз, затем **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»** и подтвердите паролем. Или в Терминале: `xattr -dr com.apple.quarantine /Applications/GlassFan.app`.

Управление вентиляторами: **Настройки → Управление вентиляторами → Установить**.
</details>
EOF
fi

cat <<EOF

### Checksums

See \`SHA256SUMS.txt\` attached below.
EOF
