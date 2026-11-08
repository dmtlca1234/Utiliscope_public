#!/bin/bash
# =============================================================================
#  UtiliScope — désinstallation / uninstaller
#
#    curl -fsSL https://raw.githubusercontent.com/dmtlca1234/Utiliscope_public/main/uninstall.sh | bash
#
#  Par défaut / By default:
#    - quitte UtiliScope et supprime /Applications/UtiliScope Beta.app ;
#    - supprime les préférences et le journal (Application Support/UtiliScope) ;
#    - CONSERVE la licence activée (.ls_license) : une réinstallation sur ce
#      Mac reste activée sans consommer une nouvelle activation.
#
#  Option --purge : supprime aussi la licence locale et réinitialise
#  l'autorisation « Enregistrement d'écran ». (La période d'essai, elle, reste
#  enregistrée dans le trousseau : réinstaller ne redonne pas 7 jours.)
#
#    curl -fsSL https://raw.githubusercontent.com/dmtlca1234/Utiliscope_public/main/uninstall.sh | bash -s -- --purge
#
#  Source of truth: the private UtiliScope repository (public/uninstall.sh).
# =============================================================================
set -euo pipefail

# Chemins surchargeables uniquement pour les tests du développeur.
APP="${UTILISCOPE_APP_PATH:-/Applications/UtiliScope Beta.app}"
PROCESS_NAME="UtiliScope Beta"
BUNDLE_ID="com.studiodmtl.utiliscope"
SUPPORT_DIR="${UTILISCOPE_SUPPORT_DIR:-$HOME/Library/Application Support/UtiliScope}"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

FIRST_LANG="$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",' || true)"
if [[ "$FIRST_LANG" == fr* ]]; then FR=1; else FR=0; fi
say() { if [[ $FR == 1 ]]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }

# 1. Quitter l'app proprement (elle sauvegarde ses préférences en quittant).
if pgrep -xq "$PROCESS_NAME"; then
    say "→ Fermeture d'UtiliScope…" "→ Quitting UtiliScope…"
    osascript -e "quit app \"$PROCESS_NAME\"" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq "$PROCESS_NAME" || break; sleep 0.5; done
    pgrep -xq "$PROCESS_NAME" && pkill -x "$PROCESS_NAME" || true
fi

# 2. L'application.
if [[ -e "$APP" ]]; then
    say "→ Suppression de $APP" "→ Removing $APP"
    # macOS protège les apps installées (« Gestion des apps ») : sans cette
    # autorisation pour Terminal, rm échoue même avec sudo. Repli : le Finder
    # (qui a toujours ce droit) met l'app à la corbeille. La première fois,
    # macOS demande d'autoriser Terminal à contrôler le Finder.
    rm -rf "$APP" 2>/dev/null || true
    if [[ -e "$APP" ]]; then
        say "  macOS protège l'app : elle est mise à la corbeille par le Finder…" \
            "  macOS protects the app: moving it to the Trash via Finder…"
        osascript -e "tell application \"Finder\" to delete (POSIX file \"$APP\" as alias)" >/dev/null 2>&1 || true
    fi
    if [[ -e "$APP" ]]; then
        say "✗ Impossible de supprimer l'app : glissez-la à la corbeille depuis Applications." \
            "✗ Could not remove the app: drag it to the Trash from Applications."
        exit 1
    fi
else
    say "  (app déjà absente : $APP)" "  (app not found: $APP)"
fi

# 3. Préférences et journal ; la licence est gardée sauf avec --purge.
if [[ -d "$SUPPORT_DIR" ]]; then
    if [[ $PURGE == 1 ]]; then
        say "→ Suppression des préférences, du journal et de la licence locale" \
            "→ Removing preferences, log and local license"
        rm -rf "$SUPPORT_DIR"
        # Réinitialise l'autorisation « Enregistrement d'écran » (réglage système,
        # pas un fichier) — sauf en mode test, où les chemins sont surchargés.
        if [[ -z "${UTILISCOPE_SUPPORT_DIR:-}" ]]; then
            tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
        fi
    else
        say "→ Suppression des préférences et du journal (licence conservée)" \
            "→ Removing preferences and log (license kept)"
        find "$SUPPORT_DIR" -mindepth 1 -maxdepth 1 ! -name ".ls_license" -exec rm -rf {} +
    fi
fi

say "✓ UtiliScope est désinstallé." "✓ UtiliScope has been uninstalled."
