# OpenShift Upgrade via ose-ansible 
The set of files to upgrade OpenShift, from 3.9 to 3.10 and 3.11, automatically, via the "ose-ansible" docker container.

# Setup Steps
## Setup local, cloned "custom-openshift-ansible" Git repo
Grab ansible host inventory files & custom openshift playbooks from the custom-openshift-ansible repo, and copy the 3.10 & 3.11 hosts fle to the cloned repo
```
git clone https://github.com/dwatson-rh/custom-openshift-ansible.git
cp <my_3.10_ansible_hosts_inventory_file> custom-openshift-ansible/hosts_<my_cluster_shortname>_3.10
cp <my_3.11_ansible_hosts_inventory_file> custom-openshift-ansible/hosts_<my_cluster_shortname>_3.11
```

## Setup local, cloned "openshift-upgrade" Git repo
Grab Docker files & scripts from the openshift-upgrade repo (and "change working directory" to it - all commands are to be ran in the
'openshift-upgrade' clone directory)
```
git clone https://github.com/dwatson-rh/openshift-upgrade.git
cd openshift-upgrade
```


## Set Environment Variables
Set OCP_VER environment variable to the version, ('3.10' or '3.11'), being upgraded (NOTE: the version is used for building & running the docker container).
```
export OCP_VER=<openshift_major_dot_minor_version>
For example, for 3.10:
export OCP_VER=3.10

For example, for 3.11:
export OCP_VER=3.11
```

Set the HOSTS_FILE environment variable to the ansible hosts inventory file
```
export HOSTS_FILE=custom-openshift-ansible/<ansible_hosts_inventory_file>
For example:
export HOSTS_FILE=custom-openshift-ansible/hosts_NONPROD_3.10
```
# Docker Build Steps
Build custom-ose-ansible docker image
```
GROUP="$(id -ng)"
GID="$(id -g)"
if [ -z "$UID" ]; then UID="$(id -u)"; fi
sudo docker build --build-arg GID=$GID --build-arg GROUP=$GROUP --build-arg
UID=$UID --build-arg USER=$USER -t custom-ose-ansible-$OCP_VER -f
Dockerfile_$OCP_VER .
```

# Docker Run Steps
## Auto Upgrade
Spin up ose-ansible-<ocp_ver> docker container, in 'auto' mode
```
if [ -z "$UID" ]; then UID="$(id -u)"; fi
sudo docker run --name custom-ose-ansible-$OCP_VER -u $uid -dit -v
$PWD/custom-openshift-ansible/:/opt/app-root/src/custom-openshift-ansible:Z -v
$HOME/.ssh/id_rsa:/opt/app-root/src/.ssh/id_rsa:Z custom-ose-ansible-$OCP_VER
auto ${HOSTS_FILE}
```

## Interactive Upgrade
Spin up ose-ansible-<ocp_ver> docker container, in 'interactive' mode
```
if [ -z "$UID" ]; then UID="$(id -u)"; fi
sudo docker run --name ose-ansible-$OCP_VER -u $UID -dit -v
$PWD/custom-openshift-ansible/:/opt/app-root/src/custom-openshift-ansible:Z -v
$HOME/.ssh/id_rsa:/opt/app-root/src/.ssh/id_rsa:Z custom-ose-ansible-$OCP_VER
```

### Pre-Installation Steps
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -check-hosts-file -m prep_verify_ansible_hosts
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_configure_docker
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_pull_docker_images
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_verify_sbin_in_path
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_fix_openshift_ansible_playbook
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_test_conn_local_yum_repo
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_local_yum_repo
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_verify_local_yum_repo
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_clean_old_etcd_backup
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_verify_local_file_systems
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_backup
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_install_excluder_packages
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_create_node_configmaps
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_set_hostname_to_fqdn
```
### Upgrade Steps

Upgrade Control Plane
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m upgrade_control_plane
```
Upgrade Infra Nodes
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m upgrade_infra_nodes
```
Upgrade App/Compute Nodes, in chunks (up to # ansible 'forks', 20)
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m upgrade_app_nodes \
  [-b <begin_node>] [-e <end_node>] [-n <openshift_upgrade_nodes_serial>]
```

Upgrade metrics
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m upgrade_metrics
```
Post-Upgrade Steps
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m post_prometheus_cluster_monitoring
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m post_verify_router_registry_and_metrics_pods
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m post_verify_integrated_registry_resolves
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m post_verify_rsyslog_still_logging
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m post_restore_yum_repo
```

### Some pre-built "repair" Steps
```
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m fix_rsyslog_logging \
  -h <FQDN_OF_SINGLE_HOST_TO_BOUNCE_RSYSLOG_AND_JOURNALD>

sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m fix_remove_label_from_nodes_in_range \
  [-b <begin_node>] [-e <end_node>] [-n <openshift_upgrade_nodes_serial>]

sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m fix_schedule_nodes_in_range \
  [-b <begin_node>] [-e <end_node>] [-n <openshift_upgrade_nodes_serial>]

sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m fix_remove_label_from_all_nodes
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m fix_schedule_all_nodes
```


