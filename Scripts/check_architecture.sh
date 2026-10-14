#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

for directory in Services State Views Managers Utilities; do
  if [[ -e "PrimaryPaste/$directory" ]]; then
    echo "Generic layer is not allowed: PrimaryPaste/$directory" >&2
    exit 1
  fi
done

if rg -n '^import SwiftUI$' PrimaryPaste/Infrastructure; then
  echo "Infrastructure must not import SwiftUI." >&2
  exit 1
fi

if rg -n '(print\(|debugPrint\(|NSLog\()' PrimaryPaste --glob '*.swift'; then
  echo "Use privacy-safe OSLog or InteractionDiagnostics in production code." >&2
  exit 1
fi

if rg -n 'recordPaste(?:Decision|Target|PassThrough).*preview|item\.preview' \
  PrimaryPaste/Features/Paste/PasteController.swift; then
  echo "Paste diagnostics must not contain captured content or previews." >&2
  exit 1
fi

if rg -n '(sk_live_|rk_live_|whsec_|-----BEGIN (?:PRIVATE|RSA|EC) KEY-----)' \
  --glob '!package-lock.json' --glob '!Scripts/check_architecture.sh' --glob '!.git/**' .; then
  echo "A secret-like value is present in the repository." >&2
  exit 1
fi

while IFS= read -r file; do
  base="$(basename "$file")"
  rg -Fq "$base in Sources" PrimaryPaste.xcodeproj/project.pbxproj || {
    echo "Xcode source membership is missing for $file" >&2
    exit 1
  }
done < <(find PrimaryPaste PrimaryPasteTests -name '*.swift' -type f | sort)

for misplaced in \
  PrimaryPaste/Features/Settings/AppsSettingsView.swift \
  PrimaryPaste/Features/Settings/PasteSettingsView.swift \
  PrimaryPaste/Features/Settings/SelectionSettingsView.swift \
  PrimaryPaste/Features/Settings/SupportSettingsView.swift; do
  if [[ -e "$misplaced" ]]; then
    echo "Capability-owned settings page is misplaced: $misplaced" >&2
    exit 1
  fi
done

echo "Architecture checks passed."
