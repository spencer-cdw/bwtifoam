#!/bin/bash
# foam — interactive OpenFOAM 9 shell
#
#   foam            open a shell in /opt/foam/cases
#   foam <dir>      open a shell in a specific case directory
#
# Container is disposable; everything under /opt/foam/cases persists.

set -e

CASES=${FOAM_CASES:-/opt/foam/cases}
IMAGE=${FOAM_IMAGE:-docker.io/openfoam/openfoam9-paraview56}
WORKDIR=${1:-}

# Use podman directly if it works; only fall back to sudo when it does not.
if podman info >/dev/null 2>&1; then
    PODMAN=podman
else
    PODMAN="sudo podman"
fi

# Rootless and rootful need different user handling, and getting it wrong
# silently corrupts file ownership on the case directory:
#
#   rootful  — the container would run as real root, so pin it to our UID.
#   rootless — podman already maps us into the container; keep-id lines the
#              two up. Adding --user here would map into the subordinate
#              range instead and files would come out owned by a stranger.
#
if [ "$($PODMAN info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ]; then
    USER_OPTS="--userns=keep-id:uid=98675,gid=98765"
    MODE=rootless
else
    USER_OPTS="--user $(id -u):$(id -g)"
    MODE=rootful
fi

# Create the case directory on first use. Never escalate here — a surprise
# password prompt is worse than a clear message.
if [ ! -d "$CASES" ]; then
    if mkdir -p "$CASES" 2>/dev/null; then
        echo "Created case directory $CASES"
    else
        cat >&2 <<MSG
Case directory does not exist and cannot be created as $(id -un):

    $CASES

Either create it once:

    sudo mkdir -p $CASES && sudo chown \$(id -u):\$(id -g) $CASES

or point somewhere you own (good for testing):

    export FOAM_CASES=\$HOME/foam-cases

MSG
        exit 1
    fi
fi

MOUNT_OPTS=""
if [ -n "$WORKDIR" ]; then
    [ -d "$CASES/$WORKDIR" ] || { echo "No such case: $CASES/$WORKDIR"; exit 1; }
    MOUNT_OPTS="-w /home/openfoam/$WORKDIR"
fi

# --- banner ------------------------------------------------------------------
# Colours only when stdout is a terminal, so piping stays clean.
if [ -t 1 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; C=$'\033[36m'; Y=$'\033[33m'; R=$'\033[0m'
else
    B=''; DIM=''; G=''; C=''; Y=''; R=''
fi

# Pad the plain text first, then colour it — otherwise printf counts the
# escape sequences in the field width and the columns drift.
pad() { printf '%-26s' "$1"; }

line() {  # line <host-path> <container-path> [note-colour]
    printf '%s│%s  %s%s%s %s→%s  %s%s%s\n' \
        "$G" "$R" "${3:-$C}" "$(pad "$1")" "$R" "$DIM" "$R" "${3:-$C}" "$2" "$R"
}

printf '\n%s┌─ OpenFOAM 9 ─────────────────────────────────────────────%s\n' "$G" "$R"
printf '%s│%s  %s%s%s %s   %s\n' "$G" "$R" "$B" "$(pad HOST)" "$R" " " "${B}CONTAINER${R}"
line "$CASES"        "/home/openfoam"
line "/tmp/.X11-unix" "/tmp/.X11-unix   (display)" "$DIM"
printf '%s│%s\n' "$G" "$R"
if [ -n "$WORKDIR" ]; then
    printf '%s│%s  starting in  %s%s%s\n' "$G" "$R" "$Y" "/home/openfoam/$WORKDIR" "$R"
else
    printf '%s│%s  starting in  %s/home/openfoam%s\n' "$G" "$R" "$Y" "$R"
fi
printf '%s│%s  %sfiles here persist on the host — the container itself does not%s\n' \
       "$G" "$R" "$DIM" "$R"
printf '%s│%s  %spodman: %s%s\n' "$G" "$R" "$DIM" "$MODE" "$R"
printf '%s└──────────────────────────────────────────────────────────%s\n\n' "$G" "$R"

# --- launch ------------------------------------------------------------------
# The case mount covers /home/openfoam, hiding the image's ~/.bashrc that would
# normally set up the OpenFOAM environment. Source it explicitly instead, then
# hand over to an interactive shell which inherits the exported variables.
INIT='for f in /opt/openfoam*/etc/bashrc; do [ -f "$f" ] && . "$f"; done; exec bash'

exec $PODMAN run --rm -it \
    $USER_OPTS \
    -v "$CASES":/home/openfoam:z \
    -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
    -e DISPLAY="$DISPLAY" \
    -e HOME=/home/openfoam \
    $MOUNT_OPTS \
    "$IMAGE" bash -c "$INIT"
