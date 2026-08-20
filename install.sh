sudo install -m 755 foam foam-run /usr/local/bin/
mkdir -p ~/.config/containers
printf '[engine]\ncgroup_manager = "cgroupfs"\n' > ~/.config/containers/containers.conf
podman run --rm docker.io/library/alpine echo ok

sudo semanage fcontext -a -t container_file_t "/opt/foam/cases(/.*)?"
sudo restorecon -Rv /opt/foam/cases
