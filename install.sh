#!/bin/bash
# =============================================================================
#  UtiliScope — installation en une commande / one-line installer
#
#    curl -fsSL https://raw.githubusercontent.com/dmtlca1234/Utiliscope_public/main/install.sh | bash
#
#  Ce que fait ce script / What this script does:
#    1. Télécharge le dernier DMG publié sur GitHub (releases/latest).
#    2. Vérifie son empreinte SHA-256, sa signature Developer ID (équipe
#       4NP3FD6KS5 — STUDIO D MTL) et sa notarisation Apple.
#    3. Copie « UtiliScope Beta.app » dans /Applications (remplace l'ancienne
#       version ; demande le mot de passe admin seulement si nécessaire).
#    4. Lance l'app : l'essai gratuit de 7 jours démarre au premier lancement.
#  Rien d'autre n'est modifié sur le Mac. Relancer la commande = mise à jour.
#
#  Variables pour les tests (développeur) :
#    UTILISCOPE_DMG_URL, UTILISCOPE_SHA_URL  — source du DMG et de son .sha256
#    UTILISCOPE_INSTALL_DIR                  — dossier cible (défaut /Applications)
#    UTILISCOPE_NO_LAUNCH=1                  — ne pas lancer l'app à la fin
#
#  Source of truth: the private UtiliScope repository (public/install.sh),
#  synced here automatically by the build. Do not edit in the public repo.
# =============================================================================
set -euo pipefail

REPO="dmtlca1234/Utiliscope_public"
ASSET="UtiliScope-Beta.dmg"
APP_NAME="UtiliScope Beta.app"
PROCESS_NAME="UtiliScope Beta"
TEAM_ID="4NP3FD6KS5"
MIN_MACOS=14
BUY_URL="https://utiliscope.xyz/"

DMG_URL="${UTILISCOPE_DMG_URL:-https://github.com/$REPO/releases/latest/download/$ASSET}"
SHA_URL="${UTILISCOPE_SHA_URL:-$DMG_URL.sha256}"
INSTALL_DIR="${UTILISCOPE_INSTALL_DIR:-/Applications}"

# --- Langue des messages : français si la première langue du Mac est le français.
FIRST_LANG="$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",' || true)"
if [[ "$FIRST_LANG" == fr* ]]; then FR=1; else FR=0; fi

say()  { if [[ $FR == 1 ]]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
step() { if [[ $FR == 1 ]]; then printf '\033[1m→ %s\033[0m\n' "$1"; else printf '\033[1m→ %s\033[0m\n' "$2"; fi; }
die()  { if [[ $FR == 1 ]]; then printf '\033[31m✗ %s\033[0m\n' "$1" >&2; else printf '\033[31m✗ %s\033[0m\n' "$2" >&2; fi; exit 1; }

# --- Nettoyage garanti : démonte le DMG et efface le dossier temporaire,
#     même si le script s'arrête en cours de route.
#     Le DMG est TOUJOURS démonté avant d'effacer le dossier temporaire ; si le
#     démontage échoue, on n'efface rien (jamais de rm -rf sur un volume monté).
TMP="$(mktemp -d -t utiliscope-install)"
MNT="$TMP/mnt"
ATTACHED=0
cleanup() {
    if [[ $ATTACHED == 1 ]]; then
        if ! hdiutil detach -quiet "$MNT" 2>/dev/null && ! hdiutil detach -quiet -force "$MNT" 2>/dev/null; then
            echo "  (DMG still mounted at $MNT — eject it in Finder)" >&2
            return
        fi
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

# --- Vérifications de signature. Important : avec `set -o pipefail`, un
#     `codesign … | grep -q …` peut échouer à tort (grep -q s'arrête au premier
#     résultat, codesign reçoit SIGPIPE). On lit donc la sortie en entier avant
#     de la comparer.
has_team_id() {   # $1 = chemin signé ; vrai si signé par l'équipe TEAM_ID
    local out
    out="$(codesign -dv "$1" 2>&1)" || return 1
    [[ "$out" == *"TeamIdentifier=$TEAM_ID"* ]]
}
is_notarized() {  # $1 = chemin ; $2 = type spctl (open | exec)
    local out
    if [[ "$2" == "open" ]]; then
        out="$(spctl -a -vv -t open --context context:primary-signature "$1" 2>&1)" || return 1
    else
        out="$(spctl -a -vv -t exec "$1" 2>&1)" || return 1
    fi
    [[ "$out" == *"Notarized Developer ID"* ]]
}

# --- 0. Prérequis ------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "UtiliScope fonctionne seulement sur macOS." \
                                      "UtiliScope only runs on macOS."
MACOS_VERSION="$(sw_vers -productVersion)"
if (( ${MACOS_VERSION%%.*} < MIN_MACOS )); then
    die "macOS $MIN_MACOS ou plus récent est requis (vous avez $MACOS_VERSION)." \
        "macOS $MIN_MACOS or later is required (you have $MACOS_VERSION)."
fi
if pgrep -xq "$PROCESS_NAME"; then
    die "UtiliScope est ouvert : quittez-le (⌘Q), puis relancez la commande." \
        "UtiliScope is running: quit it (⌘Q), then run the command again."
fi

say "UtiliScope — installation" "UtiliScope — installer"

# --- 1. Téléchargement -------------------------------------------------------
step "Téléchargement de la dernière version…" "Downloading the latest version…"
DMG="$TMP/$ASSET"
curl -fL --progress-bar "$DMG_URL" -o "$DMG" \
    || die "Téléchargement impossible. Vérifiez votre connexion." \
           "Download failed. Check your internet connection."

# --- 2. Vérifications --------------------------------------------------------
step "Vérification de l'intégrité et de la signature Apple…" \
     "Checking integrity and Apple signature…"
curl -fsSL "$SHA_URL" -o "$TMP/dmg.sha256" \
    || die "Empreinte SHA-256 introuvable : installation annulée." \
           "SHA-256 checksum not found: installation cancelled."
EXPECTED="$(awk '{print $1}' "$TMP/dmg.sha256")"
ACTUAL="$(shasum -a 256 "$DMG" | awk '{print $1}')"
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] \
    || die "Le fichier téléchargé est corrompu (empreinte différente)." \
           "The downloaded file is corrupted (checksum mismatch)."

# Signature du DMG par l'équipe Developer ID de STUDIO D MTL.
{ codesign --verify "$DMG" 2>/dev/null && has_team_id "$DMG"; } \
    || die "Signature du DMG invalide : installation annulée." \
           "Invalid DMG signature: installation cancelled."
# Notarisation Apple (Gatekeeper).
is_notarized "$DMG" open \
    || die "Le DMG n'est pas notarisé par Apple : installation annulée." \
           "The DMG is not notarized by Apple: installation cancelled."

mkdir -p "$MNT"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$DMG" \
    || die "Impossible d'ouvrir le DMG." "Could not open the DMG."
ATTACHED=1
SRC="$MNT/$APP_NAME"
[[ -d "$SRC" ]] || die "App introuvable dans le DMG." "App not found in the DMG."
{ codesign --verify --deep --strict "$SRC" 2>/dev/null && has_team_id "$SRC" \
    && is_notarized "$SRC" exec; } \
    || die "Signature de l'app invalide : installation annulée." \
           "Invalid app signature: installation cancelled."
VERSION="$(defaults read "$SRC/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"
BUILD="$(defaults read "$SRC/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "?")"

# --- 3. Installation ---------------------------------------------------------
DEST="$INSTALL_DIR/$APP_NAME"
step "Installation de la version $VERSION (build $BUILD) dans $INSTALL_DIR…" \
     "Installing version $VERSION (build $BUILD) into $INSTALL_DIR…"
mkdir -p "$INSTALL_DIR" 2>/dev/null || true
SUDO=""
if [[ ! -w "$INSTALL_DIR" ]] || { [[ -e "$DEST" ]] && [[ ! -w "$DEST" ]]; }; then
    say "Mot de passe administrateur requis pour écrire dans $INSTALL_DIR." \
        "Administrator password required to write to $INSTALL_DIR."
    SUDO="sudo"
fi
# Remplacement de l'ancienne version. macOS protège les apps installées
# (« Gestion des apps ») : sans cette autorisation pour Terminal, rm échoue
# avec « Operation not permitted », même avec sudo. Repli : le Finder (qui a
# toujours ce droit) met l'ancienne version à la corbeille. La première fois,
# macOS demande d'autoriser Terminal à contrôler le Finder.
# DEST est un chemin fixe (dossier cible + nom de l'app) : jamais vide.
if [[ -e "$DEST" ]]; then
    if ! $SUDO rm -rf "$DEST" 2>/dev/null || [[ -e "$DEST" ]]; then
        say "  macOS protège l'ancienne version : elle est mise à la corbeille par le Finder…" \
            "  macOS protects the old version: moving it to the Trash via Finder…"
        osascript -e "tell application \"Finder\" to delete (POSIX file \"$DEST\" as alias)" >/dev/null 2>&1 || true
    fi
    [[ ! -e "$DEST" ]] \
        || die "Impossible de remplacer l'ancienne version. Glissez « $APP_NAME » à la corbeille, puis relancez la commande." \
               "Could not replace the old version. Drag \"$APP_NAME\" to the Trash, then run the command again."
fi
$SUDO ditto "$SRC" "$DEST"
codesign --verify --deep --strict "$DEST" 2>/dev/null \
    || die "La copie installée est invalide. Relancez la commande." \
           "The installed copy is invalid. Run the command again."

# --- 4. Fin ------------------------------------------------------------------
echo
if [[ $FR == 1 ]]; then
    printf '\033[32m✓ UtiliScope %s (build %s) est installé.\033[0m\n' "$VERSION" "$BUILD"
    cat <<EOF

  • Essai gratuit de 7 jours : choisissez « Essai gratuit » au premier lancement.
  • macOS demandera l'autorisation « Enregistrement d'écran » : elle sert
    uniquement à lire les couleurs, rien n'est enregistré ni envoyé.
  • Acheter une licence : $BUY_URL
  • Mettre à jour : relancez la même commande.
  • Désinstaller :
      curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash

EOF
else
    printf '\033[32m✓ UtiliScope %s (build %s) is installed.\033[0m\n' "$VERSION" "$BUILD"
    cat <<EOF

  • 7-day free trial: choose "Free trial" on first launch.
  • macOS will ask for "Screen Recording" permission: it is only used to read
    colors; nothing is recorded or sent.
  • Buy a license: $BUY_URL
  • Update: run the same command again.
  • Uninstall:
      curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash

EOF
fi

if [[ "${UTILISCOPE_NO_LAUNCH:-0}" != "1" ]]; then
    open "$DEST"
fi
