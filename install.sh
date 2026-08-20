sudo install -m 755 foam foam-run /usr/local/bin/


sudo semanage fcontext -a -t container_file_t "/opt/foam/cases(/.*)?"
sudo restorecon -Rv /opt/foam/cases
