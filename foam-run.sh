#!/bin/bash
# foam-run — run a solver as a supervised background job
#
#   foam-run pitzDaily simpleFoam
#   foam-run pitzDaily simpleFoam -parallel
#
# The job is a systemd service: it survives logout, is capped so a runaway
# solver cannot take the machine down, and logs to journald.

set -e

CASES=${FOAM_CASES:-/opt/foam/cases}
IMAGE=${FOAM_IMAGE:-docker.io/openfoam/openfoam9-paraview56}
MEM=${FOAM_MEM:-16G}
CPUS=${FOAM_CPUS:-75%}

CASE=${1:-}
SOLVER=${2:-}
shift 2 2>/dev/null || true

if [ -z "$CASE" ] || [ -z "$SOLVER" ]; then
    echo "Usage: foam-run <case-dir> <solver> [solver args...]"
    echo
    echo "Example: foam-run pitzDaily simpleFoam"
    echo
    echo "Cases in $CASES:"
    ls -1 "$CASES" 2>/dev/null | sed 's/^/  /' || echo "  (none yet)"
    exit 1
fi

[ -d "$CASES/$CASE" ] || { echo "No such case: $CASES/$CASE"; exit 1; }

UNIT="foam-${CASE//[^a-zA-Z0-9]/-}"

if podman info >/dev/null 2>&1; then
    PODMAN=podman
else
    PODMAN="sudo podman"
fi

# Rootless and rootful need different handling on two counts: how the
# container user is mapped, and whether systemd-run can create a system unit.
if [ "$($PODMAN info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ]; then
    # keep-id lines the container user up with us; --user would map into the
    # subordinate range and leave case files owned by a stranger.
    USER_OPTS="--userns=keep-id"
    # Rootless cannot create system units — use the per-user manager. This
    # needs lingering to survive logout:  loginctl enable-linger $(whoami)
    RUN_SCOPE="--user"
    SUDO=""
else
    USER_OPTS="--user $(id -u):$(id -g)"
    RUN_SCOPE=""
    SUDO=""
    [ "$(id -u)" -ne 0 ] && SUDO=sudo
fi

# Refuse to silently replace a job already running for this case.
if $SUDO systemctl $RUN_SCOPE is-active --quiet "$UNIT" 2>/dev/null; then
    echo "Already running: $UNIT"
    echo "  watch:  journalctl $RUN_SCOPE -fu $UNIT"
    echo "  stop :  $SUDO systemctl $RUN_SCOPE stop $UNIT"
    exit 1
fi

echo "Starting $SOLVER on $CASE"
echo "  unit   : $UNIT"
echo "  memory : $MEM"
echo "  cpu    : $CPUS"

$SUDO systemd-run $RUN_SCOPE \
    --unit="$UNIT" \
    --description="OpenFOAM $SOLVER — $CASE" \
    --property=MemoryMax="$MEM" \
    --property=CPUQuota="$CPUS" \
    --property=Restart=no \
    --collect \
    podman run --rm --name "$UNIT" \
        $USER_OPTS \
        -v "$CASES":/home/openfoam:z \
        -e HOME=/home/openfoam \
        -w "/home/openfoam/$CASE" \
        "$IMAGE" \
        bash -c "for f in /opt/openfoam*/etc/bashrc; do [ -f \"\$f\" ] && . \"\$f\"; done; exec $SOLVER $*"

cat <<INFO

Started. The run continues after you log out.

  watch   journalctl $RUN_SCOPE -fu $UNIT
  status  systemctl $RUN_SCOPE status $UNIT
  stop    $SUDO systemctl $RUN_SCOPE stop $UNIT

INFO
