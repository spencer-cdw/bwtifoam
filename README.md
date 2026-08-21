# Openfoam 9 installer
This repo provides a script to automate spinning up openfoam using podman


## Installation

Prerequisites

- git
- podman

Install with git
```bash
cd ~/Desktop
git clone https://github.com/spencer-cdw/bwtifoam.git
cd bwtifoam
sudo ./setup.sh
```

## Updating
Because everything is managed with podman, updating is as simple as edting the install.sh or modifying a variable

```bash
cd ~/Desktop/bwtifoam
git pull
```

## Running OpenFoam
Openfoam runs inside a docker container (podman)
The docker container has a mapping to the host. To import code into openfoam the mapped directory

| Host | Container |
| --- | --- | 
| /opt/foam/cases | /home/openfoam |

```bash
cd ~/Desktop/bwtifoam
./foam.sh
```

### Copying code
Any code you want to test inside the docker (podman) container should be copied to /opt/foam/cases first. It will then be available at /home/openfoam as soon as the openfoam shell starts. 

```bash
cp foobar /opt/foam/cases
~/Desktop/bwtifoam/foam.sh
ls /home/openfoam
```

## Testing

```bash
cd ~/Desktop/bwtifoam
./foam.sh
mkdir -p $FOAM_RUN
cd $FOAM_RUN
cp -r $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily .
cd pitzDaily
blockMesh
simpleFoam
paraFoam
```

## Why 

openfoam can't be installed on rhel 9/10 due to package renaming

https://gitlab.com/openfoam/core/openfoam/-/wikis/precompiled#package-structure-rpm-partly-debianubuntu

The official docker installation was designed for containerd 
openfoam9 [script for centos 6/7](https://openfoam.org/download/9-linux/) no longer works on rhel 9/10

## Other Considerations

RHEL 10's GNOME desktop is Wayland-only; there is no Xorg login option. GUI tools launched from the container (paraFoam, ParaView) still require an X11 connection, and X11 access under Wayland is provided by XWayland, which mutter starts on demand.

The X11 authority cookie XWayland uses is not `~/.Xauthority`. It is created under the runtime directory as `.mutter-Xwaylandauth.<hash>` in `$XDG_RUNTIME_DIR`, and `$XAUTHORITY` is typically not exported in a Wayland session. If a script only checks `${XAUTHORITY:-$HOME/.Xauthority}`, that path does not exist on RHEL 10, no authority file gets mounted into the container, and GUI tools fail with `qt.qpa.xcb: could not connect to display :0` even though `DISPLAY` and the `/tmp/.X11-unix` socket are set up correctly. `foam.sh` locates the XWayland cookie directly instead of relying on `~/.Xauthority`.

Separately, RHEL's SELinux policy commonly blocks a rootless podman container from reading `/tmp/.X11-unix` even when it is bind-mounted, which produces the same connection failure independent of the authority cookie issue. `foam.sh` passes `--security-opt label=disable` on the container run to avoid this.

## Debug

If GUI tools fail to connect to the display, verify the following on the host before re-running `foam`:

```bash
echo "$XDG_SESSION_TYPE"                             # expect "wayland"
echo "$DISPLAY"                                       # display foam.sh will pass into the container
ls -la "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.*       # the XWayland authority cookie
```

If no `.mutter-Xwaylandauth.*` file exists, `foam.sh` falls back to `$XAUTHORITY` and then `~/.Xauthority`; if none of those are readable it prints a warning and runs without an authority cookie.

If the cookie exists and is readable but the connection still fails, check for an SELinux denial:

```bash
sudo ausearch -m avc -ts recent
```
