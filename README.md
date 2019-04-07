# OpenShift Upgrade via ose-ansible 
The set of files to upgrade OpenShift, from 3.9 to 3.10 and 3.11, automatically, via the "ose-ansible" docker container.

# Naming Standards 
# Host names and presumed node role (node_type)

In the ansible playbooks, there is an 11-character "host naming standard" used to determine the hosts's role:
```
  ocp<2-char_cluster_type><4-char_cluster_id><3-char_node_type><2-digit_node_number>
```
When tasks depend on the node's role (master, infra or app/compute). The 10th-12th characters of the hostname are used to set the 'node_type' ('mas', 'inf' or 'app') and the node role's tasks. 

For example, for "Non Prod" (np) cluster "AA01": 

| Hostname         | Role                                 |
|------------------|--------------------------------------|
|  ocpnpaa01mas01  |  1st master node                     |
|  ocpnpaa01inf01  |  1st infra node                      |
|  ocpnpaa01app01  |  1st app/compute/worker/minion node  |

# Ansible hosts inventory file and associated playbook files 
When a playbook file (like docker configuration) is unique to each cluster, the "cluster shortname", embeded in the name of the "ansible hosts inventory file", is used to associate the each cluster's distinct file.

The "ansible hosts inventory file naming standard" use to determine the cluster's "short name" is:
```
    hosts_<cluster_shortname>_<ocp_major_dot_minor_version>
```
For example, for the OCP 3.10 ansible hosts inventory file and docker config file for the "Non Prod" cluster "AA01":

| File Name               | File Description                       |
|-------------------------|----------------------------------------|
| Ansible inventory file  | hosts_NONPRODAA01_3.10                 |
| Docker config file      | etc__sysconfig__docker____NONPRODAA01  |


# Setup Steps
## Setup local, cloned "custom-openshift-ansible" Git repo
Grab ansible host inventory files & custom openshift playbooks from the custom-openshift-ansible repo, and copy the 3.10 & 3.11 hosts fle to the cloned repo, as well as the cluster's docker config file (to add local "Disconnected Registry"). 
```
git clone https://github.com/dwatson-rh/custom-openshift-ansible.git
cp <my_3.10_ansible_hosts_inventory_file> custom-openshift-ansible/hosts_<cluster_shortname>_3.10
cp <my_3.11_ansible_hosts_inventory_file> custom-openshift-ansible/hosts_<cluster_shortname>_3.11
cp <my_clusters_docker_cfg_file> custom-openshift-ansible/playbooks/files/etc__sysconfig__docker____<cluster_shortname>

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
export HOSTS_FILE=<ansible_hosts_inventory_file>
For example:
export HOSTS_FILE=hosts_NONPRODAA001_3.10
```
# Docker Build Steps
Build custom-ose-ansible docker image
```
GROUP="$(id -ng)"
GID="$(id -g)"
if [ -z "$UID" ]; then UID="$(id -u)"; fi
sudo docker build --build-arg GID=$GID --build-arg GROUP=$GROUP --build-arg UID=$UID --build-arg USER=$USER \
  -t custom-ose-ansible-$OCP_VER -f Dockerfile_$OCP_VER .
```

# Docker Run Steps
## Auto Upgrade - Both versions (3.10 and 3.11)
Initiate 'screen', set variables, and run the upgrade_ocp_all.sh script:
```
# Initiate 'screen' session
screen

  # Set UID, if not already set
  if [ -z "$UID" ]; then UID="$(id -u)"; fi

  # Set "HOSTS_FILES" variables for 3.10 & 3.11
  export HOSTS_FILE_310=hosts_NONPRODAA01_3.10 
  export HOSTS_FILE_311=hosts_NONPRODAA01_3.11 

  # Run single script for "push-button deploy"
  ./upgrade_ocp_all.sh
```
## Auto Upgrade - Single version (3.10 or 3.11)
Spin up ose-ansible-<ocp_ver> docker container, in 'auto' mode
```
if [ -z "$UID" ]; then UID="$(id -u)"; fi
sudo docker run --name custom-ose-ansible-$OCP_VER -u $UID -dit                   \
  -v $PWD/custom-openshift-ansible/:/opt/app-root/src/custom-openshift-ansible:Z  \
  -v $HOME/.ssh/id_rsa:/opt/app-root/src/.ssh/id_rsa:Z                            \
  custom-ose-ansible-$OCP_VER auto custom-openshift-ansible/${HOSTS_FILE}
```

## Interactive Upgrade
Spin up ose-ansible-<ocp_ver> docker container, in 'interactive' mode
```
if [ -z "$UID" ]; then UID="$(id -u)"; fi
sudo docker run --name custom-ose-ansible-$OCP_VER -u $UID -dit                   \
  -v $PWD/custom-openshift-ansible/:/opt/app-root/src/custom-openshift-ansible:Z  \
  -v $HOME/.ssh/id_rsa:/opt/app-root/src/.ssh/id_rsa:Z                            \
  custom-ose-ansible-$OCP_VER                                                     \
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
sudo docker exec -t custom-ose-ansible-$OCP_VER ./upgrade_ocp.sh -i ${HOSTS_FILE} -m prep_fix_cassandra_rc_node_selector
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


