#!/bin/bash
#set -x
function upgrade_control_plane() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ocp_get_nodes_and_pods ${hosts_file}
  ansible-playbook -i ${hosts_file}  \
    $upgrade_control_plane_playbook -e openshift_enable_unsupported_configurations=True \
    -e openshift_upgrade_nodes_serial="1" 
  return_status=$?
  if [ "$return_status" != "0" ]; then 
     usageExit 10 $hosts_file 'upgrade_control_plane' $upgrade_control_plane_playbook $return_status
  fi
  
}


function fix_rsyslog_logging() {
  local hosts_file=$1
  local single_host=$2
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ansible -i ${hosts_file} $single_host -m systemd -a 'name=rsyslog enabled=True state=restarted' 
  ansible -i ${hosts_file} $single_host -m systemd -a 'name=systemd-journald enabled=True state=restarted' 
}


function fix_remove_label_from_nodes_in_range() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  all_nodes=$(ansible -i ${hosts_file} all --list-hosts | egrep -v 'hosts \([0-9]+\)')
  if [ -z "$begin_node" ]; then
    begin_node=1
  fi
  if [ -z "$end_node" ]; then
    end_node=$(echo $all_nodes|tr ' ' '\n' |tail -1|cut -f 1 -d .|cut -c13-)
  fi
  for num in $(seq $begin_node 1  $end_node); do
    nodeNum=$(printf '%2.0d' $num|sed 's/ /0/')
    node=$(echo $all_nodes|tr ' ' '\n' |egrep "app${nodeNum}")
    if [ ! -z "$node" ]; then
      ansible masters[0] -i ${hosts_file} -a "oc label node $node upgrade-"
    fi
  done
}


function fix_schedule_nodes_in_range() {
  local hosts_file=$1
  all_nodes=$(ansible -i ${hosts_file} all --list-hosts | egrep -v 'hosts \([0-9]+\)')
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  if [ -z "$begin_node" ]; then
    begin_node=1
  fi
  if [ -z "$end_node" ]; then
    end_node=$(echo $all_nodes|tr ' ' '\n' |tail -1|cut -f 1 -d .|cut -c13-)
  fi
  for num in $(seq $begin_node 1  $end_node); do
    nodeNum=$(printf '%2.0d' $num|sed 's/ /0/')
    node=$(echo $all_nodes|tr ' ' '\n' |egrep "app${nodeNum}")
    if [ ! -z "$node" ]; then
      ansible masters[0] -i ${hosts_file} -a "oc adm manage-node ${node} --schedulable"
    fi
  done
}


function fix_remove_label_from_all_nodes() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  for node in $(ansible -i ${hosts_file} all --list-hosts | egrep -v 'hosts \([0-9]+\)'); do
    ansible -i ${hosts_file} masters[0] -a "oc label node $node upgrade-"
  done
}


function fix_schedule_all_nodes() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  for node in $(ansible -i ${hosts_file} all --list-hosts | egrep -v 'hosts \([0-9]+\)'); do
    ansible -i ${hosts_file} masters[0] -a "oc adm manage-node ${node} --schedulable"
  done
}


function upgrade_infra_nodes() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ocp_get_nodes_and_pods ${hosts_file}
  ansible-playbook -i ${hosts_file} \
  $upgrade_node_playbook \
    -e openshift_enable_unsupported_configurations=True \
    -e openshift_upgrade_nodes_label="region=infra" \
    -e openshift_upgrade_nodes_serial="6" 
  return_status=$?
  if [ "$return_status" != "0" ]; then 
     usageExit 20 $hosts_file 'upgrade_infra_nodes' $upgrade_node_playbook $return_status
  fi
  ocp_get_nodes_and_pods ${hosts_file}

}

function upgrade_metrics() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ocp_get_nodes_and_pods ${hosts_file}
  ansible-playbook -i ${hosts_file} \
    $upgrade_metrics_playbook \
    -e openshift_enable_unsupported_configurations=True 
  return_status=$?
  if [ "$return_status" != "0" ]; then 
     usageExit 30 $hosts_file 'upgrade_metrics' $upgrade_metrics_playbook $return_status
  fi

  echo -e "\nListing the image defined in the router & registry Deployment Configs, and metrics Replication Controllers ..."
  for objSpec in 'default dc/router' 'default dc/docker-registry' 'default dc/registry-console' \
  'openshift-infra rc/hawkular-cassandra-1' 'openshift-infra rc/hawkular-metrics' \
  'openshift-infra rc/heapster'; do
      ansible masters[0] -i ${hosts_file} \
      -a "oc get -n $objSpec -o jsonpath='{.spec.template.spec.containers[*].image}'"; done \
      |egrep -v '^$| SUCCESS '
    
  echo -e "\nListing the images in the router, registry, and metrics pods ..."
  ansible masters[0] -i ${hosts_file} -m shell -a "oc get pod --all-namespaces|egrep \
  'registry|router|hawkular|heapster'"|egrep -v '^$| SUCCESS ' |awk '{print $1,$2}'| while read nsPod; do 
      echo -e "\n$nsPod: \c"; \
      ansible masters[0] -i ${hosts_file} -m shell -a "oc get pod -n $nsPod -o \
      jsonpath='{.spec.containers[*].image}'"|egrep -v '^$| SUCCESS '; done \
      | egrep -v '^$'
  echo
  ocp_get_nodes_and_pods ${hosts_file}
}


function get_node_ranges () {
  local nodeStart=$1
  local end_node=$2
  local appNodeSetCount=$3
  local startIndex=0
  local nodeRanges=""
  
  nodeEnd=$[${nodeStart}+${appNodeSetCount}-1]
  while [ "$nodeEnd" -le "$end_node" ] && [ "$nodeStart" -le "$end_node" ]; do
     nodeRange="${nodeStart}-${nodeEnd}"
     nodeRanges="$nodeRanges $nodeRange"
     nodeStart=$(expr $nodeEnd + 1)
     nodeEnd=$[${nodeStart}+${appNodeSetCount}-1]
     if [ "$nodeEnd" -gt "$end_node" ]; then
       nodeEnd=$end_node
     fi
  done
  echo $nodeRanges
}
  

function prep_host_file_for_node_range() {
  local hosts_file=$1
  local nodeRange=$2

  new_hosts_file="/tmp/ocpUpgrade__$(basename "$hosts_file")"

  #echo "DFW HERE 7.1 hosts_file ==>$hosts_file<==" > /tmp/dfw.jnk
  #echo "DFW HERE 7.2 nodeRange ==>$nodeRange<==" >> /tmp/dfw.jnk 
  #echo "DFW HERE 7.3 new_hosts_file ==>$new_hosts_file<==" >> /tmp/dfw.jnk

  nodeStart=$(echo "${nodeRange}"|cut -f1 -d-)
  nodeEnd=$(echo "${nodeRange}"|cut -f2 -d-)
  regExpStr=$(for num in $(seq ${nodeStart} 1 ${nodeEnd}); do echo -e "app$(printf '%2.0d' $num|sed 's/ /0/')|\c"; done|sed "s/|$//")

  nodesLine=$[$(grep -n "^\[app-nodes" $hosts_file| cut -f1 -d:)-1]

  head -${nodesLine} $hosts_file > $new_hosts_file
  echo '[app-nodes]' >> $new_hosts_file

  #For SRK Test, the region label is different, for "prod fix" nodes, and some hosts are defined with ranges
  if (grep -q "^\[pf-app-nodes]" $hosts_file); then
    reg_nodes=$(ansible -i ${hosts_file} reg-app-nodes --list-hosts |tr '\n' ' ')
    pf_nodes=$(ansible -i ${hosts_file} pf-app-nodes --list-hosts |tr '\n' ' ')
    echo "${regExpStr}" | tr '|' '\n' | awk '{print $1}'| while read node_a
    do
      node_reg=$(echo $reg_nodes|tr ' ' '\n' |grep $node_a)
      if [ ! -z "$node_reg" ]; then
        echo "$node_reg openshift_node_labels=\"{'region': 'app'}\"" >> $new_hosts_file
      else
        node_pf=$(echo $pf_nodes|tr ' ' '\n' |grep $node_a)
        if [ ! -z "$node_pf" ]; then
          echo "$node_pf openshift_node_labels=\"{'region': 'ips-prod-fix'}\"" >> $new_hosts_file
        fi
      fi
    done
  else 
    echo "${regExpStr}" | tr '|' '\n' | awk '{print $1}'| while read node_a
    do
      grep "$node_a" $hosts_file |tail -1 >> $new_hosts_file
    done
  fi
  echo "$new_hosts_file"
}
  

function upgrade_app_nodes() {
  #echo "DFW HERE 2 hosts_file==>${hosts_file}<=="
  local hosts_file=$1
  forks=20
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  if [ -z "$begin_node" ]; then
    begin_node=1
  fi
  if [ -z "$end_node" ]; then
    end_node=$(ansible -i ${hosts_file} nodes --list-hosts|grep app |tail -1|tr -d ' '|cut -f 1 -d .|cut -c13-)
  fi
  possible_num_of_nodes_range=$(expr $end_node - $begin_node + 1)
  if [ -z "$nodes_serial" ]; then
    if [ "$forks" -lt "$possible_num_of_nodes_range" ]; then    
      nodes_serial=${forks}
    else
      if [ "$( bc <<< "scale=0; (${possible_num_of_nodes_range}/2)*10")" = "$(bc <<< "scale=1; (${possible_num_of_nodes_range}/2)*10"|cut -f1 -d.)" ]; then
        nodes_serial=$(bc <<< "scale=0; (${possible_num_of_nodes_range}/2)")
      else
        nodes_serial=$(bc <<< "scale=0; ((${possible_num_of_nodes_range}/2)+1)")
      fi
    fi
  elif [ "$nodes_serial" -gt  "$possible_num_of_nodes_range" ]; then
    nodes_serial=$possible_num_of_nodes_range
  elif [ "$nodes_serial" -gt "$forks" ]; then
    nodes_serial=$forks
  fi
  nodeRanges="$(get_node_ranges $begin_node $end_node $nodes_serial)"
  echo "Node range sets are: $nodeRanges"
  ocp_get_nodes_and_pods ${hosts_file}

  for nodeRange in $nodeRanges; do
    echo -e "\n\n\t****\tUpgrading nodes in range: ${nodeRange}\t****"
    # Create hosts inventory file for just the app nodes in the range
    tmp_host_file="$(prep_host_file_for_node_range ${hosts_file} ${nodeRange})"

    #DFW temporarily copy these, for debugging
    #tmp_host_file_copy="${tmp_host_file}__$$__$(date +"%m/%d/%y %H:%M:%S" |  sed 's/\///g' | sed 's/ /_/g' | sed 's/://g'|cut -f1 -d.)"
    #cp $tmp_host_file $tmp_host_file_copy

    # Unschedule & label all app nodes in the range
    numUpgradeNode=0
    for num in $(seq $(echo $nodeRange|cut -f1 -d-) 1  $(echo $nodeRange|cut -f2 -d-)); do
      nodeNum=$(printf '%2.0d' $num|sed 's/ /0/')
      node=$(ansible all -i ${tmp_host_file} --list-hosts|egrep "app${nodeNum}"|tr -d ' ')
      if [ ! -z "$node" ]; then
        let numUpgradeNode=$numUpgradeNode+1
        ansible masters[0] -i ${tmp_host_file} -a "oc adm manage-node ${node} --schedulable=False"
        ansible masters[0] -i ${tmp_host_file} -a "oc label node $node upgrade=app_round"
      fi
    done
   
    # Verify all nodes with upgrade=app_round label match the nodes in the range
    numNodeLabeledUpgrade=$(ansible masters[0] -i ${tmp_host_file} -m shell -a "oc get node -l 'upgrade=app_round' -L upgrade -L region|egrep 'compute.*app_round'|wc -l"|egrep -v '^[a-z]'|egrep '[0-9]')
    
    if [ "$numNodeLabeledUpgrade" = "0No resources found." ]; then
      usageExit 6 ${tmp_host_file} 0 $numUpgradeNode $nodeRange
    elif [ "$numNodeLabeledUpgrade" != "$numUpgradeNode" ]; then
      usageExit 6 ${tmp_host_file} "$numNodeLabeledUpgrade" $numUpgradeNode $nodeRange
    fi
   
    
    # Drain all app nodes in the range
    for num in $(seq $(echo $nodeRange|cut -f1 -d-) 1  $(echo $nodeRange|cut -f2 -d-)); do
      nodeNum=$(printf '%2.0d' $num|sed 's/ /0/')
      node=$(ansible all -i ${tmp_host_file} --list-hosts|egrep "app${nodeNum}"|tr -d ' ')
      if [ ! -z "$node" ]; then
        ansible masters[0] -i ${tmp_host_file} -a "oc adm drain --force --delete-local-data --ignore-daemonsets=True $node"
      fi
    done

    
    # Upgrade all app nodes in the range
    ansible-playbook -i ${tmp_host_file}  \
    $upgrade_node_playbook \
      -e openshift_enable_unsupported_configurations=True \
      -e openshift_upgrade_nodes_label="upgrade=app_round" \
      -e openshift_upgrade_nodes_serial="${nodes_serial}"
    return_status=$?
    if [ "$return_status" != "0" ]; then 
      usageExit 40 $hosts_file 'upgrade_app_nodes' $upgrade_node_playbook $return_status $nodeRange
    fi
  
  
    # Re-schedule & unlabel all app nodes in the range
    for num in $(seq $(echo $nodeRange|cut -f1 -d-) 1  $(echo $nodeRange|cut -f2 -d-)); do
      nodeNum=$(printf '%2.0d' $num|sed 's/ /0/')
      node=$(ansible all -i ${tmp_host_file} --list-hosts|egrep "app${nodeNum}"|tr -d ' ')
      if [ ! -z "$node" ]; then
        ansible masters[0] -i ${tmp_host_file} -a "oc adm manage-node ${node} --schedulable=True"
        ansible masters[0] -i ${tmp_host_file} -a "oc label node $node upgrade-"
      fi
    done
 
    ocp_get_nodes_and_pods ${tmp_host_file}
  done
}
function ocp_get_nodes_and_pods() {
  local hosts_file=$1
  # Get nodes
  ansible masters[0] -i ${hosts_file} -a 'oc get node -o wide'

  # Get all pods
  ansible masters[0] -i ${hosts_file} -a 'oc get pod --all-namespaces -o wide'

}

function usageExit() { 
  local exitStatus=$1
  local hosts_file=$2
  case "${exitStatus}" in
    1)
        ErrMsg="Invalid Option. Avaliable options are: 'i|m|l|n|b|e'"
        ;;
    2)
        ErrMsg="Invalid Method. Available methods are: 'prep_verify_ansible_hosts|prep_configure_docker|prep_pull_docker_images\n\t    |prep_verify_sbin_in_path|prep_fix_openshift_ansible_playbook\n\t    |prep_test_conn_local_yum_repo|prep_local_yum_repo|prep_verify_local_yum_repo\n\t    |prep_clean_old_etcd_backup|prep_verify_local_file_systems|prep_backup\n\t    |prep_install_excluder_packages|prep_create_node_configmaps\n\t    |prep_prometheus_cluster_monitoring|prep_fix_cassandra_rc_node_selector|prep_set_hostname_to_fqdn\n\t    |upgrade_control_plane|upgrade_infra_nodes|upgrade_app_nodes|upgrade_all|upgrade_metrics\n\t    |fix_remove_label_from_nodes_in_range|fix_schedule_nodes_in_range|fix_remove_label_from_all_nodes\n\t    |fix_schedule_all_nodes|fix_rsyslog_logging\n\t    |post_verify_router_registry_and_metrics_podn\t    |post_verify_integrated_registry_resolves|post_verify_rsyslog_still_logging\n\t    |post_restore_yum_repo|post_prometheus_cluster_monitoring'"
        ;;
    3)
        ErrMsg="Missing ansible inventory hosts file\n\tPlease provide \"-i <ansible_hosts_inventory_file>\""
        ;;
    4)
        ErrMsg="Can't find ansible inventory hosts file: ${hosts_file}"
        ;;
    5)
        ErrMsg="Can't ssh and run sudo on a node in the ansible inventory hosts file: ${hosts_file}"
        echo -e "${ErrMsg}"
        ansible -i $hosts_file all -m ping  2>/dev/null| egrep '^[a-z]'|grep -v 'SUCCESS'
        ;;
    8)
        ErrMsg="Invalid host group: '$3' for ansible inventory hosts file, '${hosts_file}', which has host groups: $4"
        echo -e "${ErrMsg}"
        ;;
    6)
        ErrMsg="The number of nodes labeled for upgrade, $3, does not match the number of nodes ($4) in upgrade range, $5"
        echo -e "${ErrMsg}\n"
        exit $exitStatus
        ;;
    7)
        ErrMsg="The openshift_release, $3, in hosts file, $2, does NOT match the openshift-ansible package version, $4"
        echo -e "${ErrMsg}\n"
        exit $exitStatus
        ;;
    10|20|30)
        ErrMsg="The $3 function's playbook, $4, failed with exit status: $5"
        echo -e "${ErrMsg}\n"
        exit $exitStatus
        ;;
    40|41|42|43)
        ErrMsg="The $3 function's playbook, $4, failed with exit status: $5, while in 'node range': $6"
        echo -e "${ErrMsg}\n"
        exit $exitStatus
        ;;
    9|60|61|62|65|66|67|68|70|71|72|73|74|75|77|78|79|80|81|85|86|87|88|89|90|91|92|93|95|96|100|110|111|112|113|120|130|135|140|141|145|146|147|148|149|201|202|203|204|235|240|241|246)
        ErrMsg="The $3 function failed with message: $4"
        echo -e "${ErrMsg}\n"
        exit $exitStatus
        ;;
    50)
        ErrMsg="The fix_rsyslog_logging method requires a specific, single host to be specified, via '-h' parameter"
        echo -e "${ErrMsg}\nUsage: $0 -i <ansible_hosts_inventory_file> -m fix_rsyslog_logging -h single_host_for_fixing_syslog [-check-hosts-file]" 1>&2
        exit $exitStatus
        ;;
    *)
        ErrMsg="Unkown Error"
        exitStatus=99
        ;;
  esac
  echo -e "\n\033[31m${ErrMsg}\033[0m\n\nUsage: $0 -i <ansible_hosts_inventory_file> \\ \n\t-m 'prep_verify_ansible_hosts|prep_configure_docker|prep_pull_docker_images\n\t    |prep_verify_sbin_in_path|prep_fix_openshift_ansible_playbook\n\t    |prep_test_conn_local_yum_repo|prep_local_yum_repo|prep_verify_local_yum_repo\n\t    |prep_clean_old_etcd_backup|prep_verify_local_file_systems|prep_backup\n\t    |prep_install_excluder_packages|prep_create_node_configmaps\n\t    |prep_prometheus_cluster_monitoring|prep_fix_cassandra_rc_node_selector|prep_set_hostname_to_fqdn\n\t    |upgrade_control_plane|upgrade_infra_nodes|upgrade_app_nodes|upgrade_all|upgrade_metrics\n\t    |fix_remove_label_from_nodes_in_range|fix_schedule_nodes_in_range|fix_remove_label_from_all_nodes\n\t    |fix_schedule_all_nodes|fix_rsyslog_logging\n\t    |post_verify_router_registry_and_metrics_pods\n\t    |post_verify_integrated_registry_resolves|post_verify_rsyslog_still_logging\n\t    |post_restore_yum_repo|post_prometheus_cluster_monitoring' \\ \n\t[-g <host_group>] [-b <begin_node>] [-e <end_node>] [-n <openshift_upgrade_nodes_serial>]\n\t[-check-hosts-file] [-h single_host_for_fixing_syslog]" 1>&2
  exit $exitStatus
}

#Pre-Installation Functions
function prep_verify_ansible_hosts() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  if ! (ansible -i ${hosts_file} all -m ping 1>/dev/null 2>&1); then
    usageExit 5 $hosts_file
  fi

  ans_output=$(ansible -i ${hosts_file} masters[0] -m oc_serviceaccount -a 'name=drain-node-sa namespace=openshift' --check; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 9 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Verified Ansible can ping all nodes, as root, and can run OpenShift roles and modules"
  fi

}

function prep_configure_docker() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  local hosts_file_dir="$(dirname $hosts_file)/.."
  local secure_docker_playbook=${hosts_file_dir}/playbooks/secure-docker.yml
  local secure_docker_playbook_basename=$(basename $secure_docker_playbook)

  ocp_get_nodes_and_pods ${hosts_file}

  if [ ! -f $secure_docker_playbook ]; then
    usageExit 95 $hosts_file $FUNCNAME "Failed to configure docker, as $secure_docker_playbook does NOT exist"
  fi


  #local tmp_host_file="/tmp/ocpUpgrade__confDocker__$(basename "$hosts_file")"
  local tmp_host_file="/tmp/$(basename "$hosts_file")__ocpUpgrade__confDocker"

  forks=20

  # set default to 0, to NOT set end_node, for each ans_host_group
  setEndNode=0
  
  # For debugging ansible commands used to unschedule, drain, secure, and re-schedule, use 'runAnsible' 
  # set 'runAnsible' default to 0, to NOT run (just echo) ansible commands
  runAnsible=0
  # set 'runAnsible' default to 1, to RUN ansible commands
  #runAnsible=1
  
  if [ -z "$ans_host_group" ]; then
    local_ans_host_group_set="masters infra-nodes app-nodes"
    begin_node=1
    setEndNode=1
  else 
    local_ans_host_group_set=$ans_host_group
    if [ -z "$begin_node" ]; then
      begin_node=1
    fi
    if [ -z "$end_node" ]; then
      end_node=$(ansible -i ${hosts_file} ${ans_host_group} --list-hosts|tail -1|tr -d ' '|cut -f 1 -d .|cut -c13-)
    fi
  fi

  # Loop thru each "ansible host group"
  for ans_host_group in $local_ans_host_group_set;  do
    # If setEndNode set, then re-set end_node for each "ansible host group"
    if (( $setEndNode )); then
      end_node=$(ansible -i ${hosts_file} ${ans_host_group} --list-hosts|tail -1|tr -d ' '|cut -f 1 -d .|cut -c13-)
    fi
    possible_num_of_nodes_range=$(expr $end_node - $begin_node + 1)
    if (( $setEndNode )) || [ -z "$nodes_serial" ]; then
      if [ "$forks" -lt "$possible_num_of_nodes_range" ]; then    
        nodes_serial=${forks}
      else
        if [ "$( bc <<< "scale=0; (${possible_num_of_nodes_range}/2)*10")" = "$(bc <<< "scale=1; (${possible_num_of_nodes_range}/2)*10"|cut -f1 -d.)" ]; then
          nodes_serial=$(bc <<< "scale=0; (${possible_num_of_nodes_range}/2)")
        else
          nodes_serial=$(bc <<< "scale=0; ((${possible_num_of_nodes_range}/2)+1)")
        fi
      fi
    elif [ "$nodes_serial" -gt  "$possible_num_of_nodes_range" ]; then
      nodes_serial=$possible_num_of_nodes_range
    elif [ "$nodes_serial" -gt "$forks" ]; then
      nodes_serial=$forks
    fi

    nodeRanges="$(get_node_ranges $begin_node $end_node $nodes_serial)"

    for nodeRange in $nodeRanges; do
      echo -e "\n\n\t****\tConfiguring docker on '${ans_host_group}' nodes in range: ${nodeRange}\t****"

      # Intialize temporary ansible host inventory file
      echo -e "[OSEv3:children]\nnodes\n" >  ${tmp_host_file}
      lineNo=$(expr $(egrep -n '^\['  ${hosts_file} | grep -v OSEv3 |head -1|cut -f1 -d:) - 1)
      tailLine=$(expr $lineNo - $(egrep -n '^\[OSEv3:vars'  ${hosts_file}|cut -f1 -d:) + 1)
      head -$lineNo  ${hosts_file} |tail -$tailLine >> ${tmp_host_file}
      echo  "[nodes]" >> ${tmp_host_file}

      # Build temp host file for all nodes in the range, for "ansible host group" (ans_host_group)
      for num in $(seq $(echo $nodeRange|cut -f1 -d-) 1  $(echo $nodeRange|cut -f2 -d-)); do
        nodeNum=$(printf '%2.0d' $num|sed 's/ /0/')
        node=$(ansible $ans_host_group -i ${hosts_file} --list-hosts| egrep -v 'hosts \([0-9]+\)'|egrep "${nodeNum}"|tr -d ' ')
        if [ ! -z "$node" ]; then
          echo "$node" >> ${tmp_host_file}
        fi
      done

      # Create list of nodes in the range, for "ansible host group", using temp host file
      nodes_in_range=$(ansible -i ${tmp_host_file} all --list-hosts 2>/dev/null |egrep -v 'hosts \([0-9]+\)')
  
      # Configure docker, only if there are nodes in the range, for "ansible host group"
      if [ -z "$nodes_in_range" ]; then
        echo "There are no nodes in this range, for "ansible host group", '${ans_host_group}'"
      else
        actual_nodes_in_range_count=$(echo "${nodes_in_range}"|wc -l)
        actual_nodes_in_range_start=$(echo "${nodes_in_range}"|tr -d ' ' |cut -f1 -d. | cut -c13-|sort -n|head -1)
        actual_nodes_in_range_stop=$(echo "${nodes_in_range}"|tr -d ' ' |cut -f1 -d. | cut -c13-|sort -n|tail -1)

        echo -e "\nAbout to unschedule, drain pods, replace /etc/sysconfig/docker, bounce docker & re-schedule the following $actual_nodes_in_range_count node(s) (${actual_nodes_in_range_start}-${actual_nodes_in_range_stop}):"
        echo "$nodes_in_range"|sort
        echo


        # Unschedule all nodes in the range, for "ansible host group" 
        for node in $nodes_in_range; do

          # If 'runAnsible' set to 0, just echo ansible command (do NOT run)
          if (( $runAnsible )); then
            # Run ansible
            ansible masters[0] -i ${hosts_file} -a "oc adm manage-node ${node} --schedulable=False"
            return_status=$?
            if [ "$return_status" != "0" ]; then
              usageExit 96 $hosts_file $FUNCNAME "Failed to unschedule node  ${node} "
            fi
          else
            # Debug mode
            echo ansible masters[0] -i ${hosts_file} -a "oc adm manage-node ${node} --schedulable=False"
          fi
        done

        # Drain any node in the range, for "ansible host group"
        for node in $nodes_in_range; do

          # If 'runAnsible' set to 0, just echo ansible command (do NOT run)
          if (( $runAnsible )); then
            # Run ansible
            ansible masters[0] -i ${hosts_file} -a "oc adm drain --force --delete-local-data --ignore-daemonsets=True $node"
            return_status=$?
            if [ "$return_status" != "0" ]; then
              usageExit 96 $hosts_file $FUNCNAME "Failed to drain node  ${node} "
            fi
          else
            # Debug mode
            echo ansible masters[0] -i ${hosts_file} -a "oc adm drain --force --delete-local-data --ignore-daemonsets=True $node"
          fi
        done
  
        # Replace /etc/sysconfig/docker & bounce docker, on all nodes in the range, for "ansible host group"

        # If 'runAnsible' set to 0, just echo ansible command (do NOT run)
        if (( $runAnsible )); then
          # Run ansible
          ansible-playbook -i ${tmp_host_file} ${hosts_file_dir}/playbooks/run-playbooks.yml -e playbooks="['$secure_docker_playbook_basename']"
          return_status=$?
          if [ "$return_status" != "0" ]; then
            usageExit 96 $hosts_file $FUNCNAME "The secure-docker playbook failed to replace /etc/sysconfig/docker and/or restart docker"
          fi
        else
          # Debug mode
          echo ansible-playbook -i ${tmp_host_file} ${hosts_file_dir}/playbooks/run-playbooks.yml -e playbooks="['$secure_docker_playbook_basename']"
        fi

        # Try to fix odd error re-scheduling DEV mas01
        sleepInterval=15
        if [ "$actual_nodes_in_range_count" = "1" ]; then
          node_type_hostname=$(echo $nodes_in_range|cut -c10-12)
          if [ "$node_type_hostname" = "mas" ]; then
            echo "Sleeping for '$sleepInterval' seconds, to wait for 'kube-system' pods to become ready on a single master . . ."
            sleep $sleepInterval;
          fi
        fi

        # Re-schedule any node in the range, for "ansible host group"
        for node in $nodes_in_range; do

          # If 'runAnsible' set to 0, just echo ansible command (do NOT run)
          if (( $runAnsible )); then
            # Run ansible
            ansible masters[0] -i ${hosts_file} -a "oc adm manage-node ${node} --schedulable=True"
            return_status=$?
            if [ "$return_status" != "0" ]; then
              usageExit 96 $hosts_file $FUNCNAME "Failed to re-schedule node  ${node} "
            fi
          else
            # Debug mode
            echo ansible masters[0] -i ${hosts_file} -a "oc adm manage-node ${node} --schedulable=True"
          fi
        done

      fi

    ocp_get_nodes_and_pods ${hosts_file}
    # End of "nodeRanges" for loop
    done


  # End of "ansible host group" for loop
  done
 

}

function prep_pull_docker_images() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ansible-playbook -i ${hosts_file} custom-openshift-ansible/playbooks/ocp-upgrade-prep.yml -e pull_docker_images=true
  return_status=$?
  if [ "$return_status" != "0" ]; then
    usageExit 145 $hosts_file $FUNCNAME "The ocp-upgrade-prep playbook failed to pull images"
  fi
}


function prep_verify_sbin_in_path() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible all -i ${hosts_file} -m shell -a "env|egrep '^PATH=.*\/sbin'"; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 100 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Verified '/sbin' in path"
  fi

}

function prep_verify_local_file_systems() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  local fs_pct_threshold=90
  local fs_output=""
  local test_fail=false
  for node in $(ansible -i ${hosts_file} masters --list-hosts | egrep -v 'hosts \([0-9]+\)'); do
    var_lib_etcd_avail_kb=$(ansible $node -i ${hosts_file} -m shell -a "df -k /var/lib/etcd|grep dev/mapper|tr -s '[:space:]' | tr ' ' '~'|cut -f4 -d~"|grep -v  SUCCESS )
    #echo "DFW HERE 1 Checking $node ..."
    if ! (echo "$var_lib_etcd_avail_kb" 2>/dev/null|egrep -q '^[0-9]+$'); then
      usageExit 110 $hosts_file $FUNCNAME "'/var/lib/etcd' Available Disk Space: '$var_lib_etcd_avail_kb', is NOT numeric"
    fi
    etcd_db_kb=$(ansible $node -i ${hosts_file} -m shell -a "du -ks /var/lib/etcd/member"|grep -v  SUCCESS |awk '{print $1}')
    if ! (echo "$etcd_db_kb" 2>/dev/null|egrep -q '^[0-9]+$'); then
      usageExit 111 $hosts_file $FUNCNAME "'/var/lib/etcd/member' Disk Space Used: '$etcd_db_kb', is NOT numeric"
    fi
    #var_lib_etcd_reqd_kb=$(echo $[($etcd_db_kb*2)+8])
    var_lib_etcd_reqd_kb=$(bc <<< "scale=3; $etcd_db_kb*2.3"|cut -f1 -d.)
    #echo "DFW HERE 9.1 var_lib_etcd_reqd_kb ==>$var_lib_etcd_reqd_kb<=="
    #echo "DFW HERE 9.2 var_lib_etcd_avail_kb ==>$var_lib_etcd_avail_kb<=="
    echo "/var/lib/etcd has $var_lib_etcd_avail_kb on $node and requires $var_lib_etcd_reqd_kb"
    if [ "$var_lib_etcd_avail_kb" -lt "$var_lib_etcd_reqd_kb" ]; then 
      usageExit 112 $hosts_file $FUNCNAME "insufficient disk space for etcd backup: $var_lib_etcd_reqd_kb KB disk space required for etcd backup, but only $var_lib_etcd_avail_kb KB is available."
    fi
  done
  for node in $(ansible -i ${hosts_file} all --list-hosts | egrep -v 'hosts \([0-9]+\)'); do
    #echo "DFW HERE 2 Checking $node ..."
    for line in $(ansible $node -i ${hosts_file} -m shell -a "df -h |grep dev/mapper|sort -nk 5|tail -6| tr -s '[:space:]' |tr ' ' '~'|cut -f5-6 -d~"|grep -v  SUCCESS ); do
      fs_pct=$(echo $line|cut -f1 -d%)
      fs_mount=$(echo $line|cut -f2 -d~)
      if [ "$fs_pct" -ge "$fs_pct_threshold" ];then
        test_fail=true
        fs_output="$fs_output\n$node $fs_pct $fs_mount"
      fi
    done
  done
  if $test_fail; then
    usageExit 113 $hosts_file $FUNCNAME "$fs_output"
  else
    echo "Verified all file systems"
  fi
}


function prep_test_conn_local_yum_repo() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible all -i ${hosts_file} -m shell -a \
    "wget http://mylocal.yumrepo.fqdn/repos/ocp${yum_repo_ver}/rhel-7-server-ose-${ocp_version}-rpms/repodata/repomd.xml; rm repomd.xml"  2>&1; echo $? )
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 120 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Verified connection to local yum repo, http://mylocal.yumrepo.fqdn/repos/ocp${yum_repo_ver}/rhel-7-server-ose-${ocp_version}-rpms/repodata/repomd.xml"
  fi
}


function prep_local_yum_repo() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible-playbook -i ${hosts_file} custom-openshift-ansible/playbooks/ocp-upgrade-prep.yml \
     -e prep_local_yum_repo=true; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 146 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Prepared local yum repo access to $openshift_image_tag"
  fi
}


function prep_verify_local_yum_repo() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible all -i ${hosts_file} -m shell -a 'yum --showduplicates list atomic-openshift|grep "$openshift_image_tag"'; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 130 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Verified local yum repo access to $openshift_image_tag"
  fi
}


function prep_clean_old_etcd_backup() {
  local hosts_file=$1

  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  local hosts_file_dir="$(dirname $hosts_file)/.."
  local clean_old_etcd_backup_playbook=${hosts_file_dir}/playbooks/clean_old_etcd_backup.yml
  local clean_old_etcd_backup_playbook_basename=$(basename $clean_old_etcd_backup_playbook)

  if [ ! -f $clean_old_etcd_backup_playbook ]; then
    usageExit 92 $hosts_file $FUNCNAME "Failed to clean old etcd backup directories, as $clean_old_etcd_backup_playbook does NOT exist"
  fi

  # Clean old etcd backup directories
  ansible-playbook -i ${hosts_file} -l masters ${hosts_file_dir}/playbooks/run-playbooks.yml -e playbooks="['$clean_old_etcd_backup_playbook_basename']"
  return_status=$?
  if [ "$return_status" != "0" ]; then
    usageExit 93 $hosts_file $FUNCNAME "Failed to run $clean_old_etcd_backup_playbook_basename playbook"
  else
    echo "Cleaned etcd backed up directories"
  fi
}

function prep_backup() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible-playbook -i ${hosts_file} custom-openshift-ansible/playbooks/ocp-upgrade-prep.yml \
     -e backup_ocp=true; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 147 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Backed up existing files"
  fi

}


function prep_install_excluder_packages() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible all -i ${hosts_file} -a 'yum install -y atomic-openshift-excluder atomic-openshift-docker-excluder'; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 148 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Installed excluder packages"
  fi
}

function prep_create_node_configmaps() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible-playbook -i ${hosts_file} \
     /usr/share/ansible/openshift-ansible/playbooks/openshift-master/openshift_node_group.yml; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 149 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Created node ConfigMaps"
  fi
}

function prep_fix_openshift_ansible_playbook() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  hosts_file_dir="$(dirname $hosts_file)/.."
  local playbook_to_fix="/usr/share/ansible/openshift-ansible/roles/openshift_control_plane/tasks/check_master_api_is_ready.yml"
  local fixed_playbook="${hosts_file_dir}/misc_files/ocp_${playbook_dir}__$(echo $playbook_to_fix|sed 's/\//__/g')"
  if [ ! -f $fixed_playbook ]; then
    usageExit 80 $hosts_file $FUNCNAME "Failed to fix playbook, as $fixed_playbook does NOT exist"
  fi
  if ! (cp $fixed_playbook $playbook_to_fix); then
    usageExit 81 $hosts_file $FUNCNAME "Failed to fix playbook, as 'cp $fixed_playbook $playbook_to_fix' command failed"
  fi
}


function prep_fix_cassandra_rc_node_selector() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"

  # Get nodeSelector for cassandra Replication Controller
  cass_node_selector=$(ansible masters[0] -i ${hosts_file} -a "oc get -n openshift-infra rc/hawkular-cassandra-1 -o jsonpath='{.spec.template.spec.nodeSelector}'"| grep -v ' SUCCESS ')
  if [ "$cass_node_selector" != "map[region:infra]" ]; then 
    echo "Adding node selector to cassandra Replication Controller ..."
    if ! (ansible masters[0] -i ${hosts_file} -a "oc patch -n openshift-infra rc/hawkular-cassandra-1 -p '{\"spec\": {\"template\": {\"spec\": { \"nodeSelector\": {\"region\":\"infra\"}}}}}'"); then 
        usageExit 90 $hosts_file $FUNCNAME echo "Failed to patch Cassandra Replication Controller's node selector"
    fi

    #Fail, if still not able to verify 
    cass_node_selector=$(ansible masters[0] -i ${hosts_file} -a "oc get -n openshift-infra rc/hawkular-cassandra-1 -o jsonpath='{.spec.template.spec.nodeSelector}'"| grep -v ' SUCCESS ')
    if [ "$cass_node_selector" != "map[region:infra]" ]; then 
         usageExit 91 $hosts_file $FUNCNAME "Failed to match Cassandra Replication Controller's node selector to 'region=infra'"
    fi    

    # Don't restart pod, as metrics upgrade playook should restart
  fi

  echo "Verified Cassandra Replication Controller's node selector"
}


function prep_set_hostname_to_fqdn() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  local hosts_file_dir="$(dirname $hosts_file)/.."
  local set_hostname_playbook=${hosts_file_dir}/playbooks/set_hostname_to_fqdn.yml
  local set_hostname_playbook_basename=$(basename $set_hostname_playbook)
  if [ ! -f $set_hostname_playbook ]; then
    usageExit 85 $hosts_file $FUNCNAME "Failed to set hostname to FQDN, as $set_hostname_playbook does NOT exist"
  fi


  # Set hostname to FQDN
  ansible-playbook -i ${hosts_file} ${hosts_file_dir}/playbooks/run-playbooks.yml -e playbooks="['$set_hostname_playbook_basename']"
  return_status=$?
  if [ "$return_status" != "0" ]; then
    usageExit 86 $hosts_file $FUNCNAME "Failed to run $set_hostname_playbook playbook"
  fi
}


#Post-Installation Functions
function post_verify_router_registry_and_metrics_pods() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"

  # Set list of objects, based on openshift_metrics_install_metrics
  objFullSpecList="default:dc/router:ose-haproxy-router:$openshift_image_tag default:dc/docker-registry:ose-docker-registry:$openshift_image_tag default:dc/registry-console:registry-console:$openshift_image_tag" 
  
  podSpecList="default:router:ose-haproxy-router:$openshift_image_tag default:docker-registry:ose-docker-registry:$openshift_image_tag default:registry-console:registry-console:$openshift_image_tag" 
  
  if [ "$openshift_metrics_install_metrics" = "true" ]; then 
    pod_check_string="'registry|router|hawkular|heapster'|egrep -v '^\$| SUCCESS |hawkular-metrics-schema'"
    objFullSpecList="$objFullSpecList openshift-infra:rc/hawkular-cassandra-1:metrics-cassandra:$openshift_metrics_image_version openshift-infra:rc/hawkular-metrics:metrics-hawkular-metrics:$openshift_metrics_image_version openshift-infra:rc/heapster:metrics-heapster:$openshift_metrics_image_version"
    podSpecList="$podSpecList openshift-infra:hawkular-cassandra-1:metrics-cassandra:$openshift_metrics_image_version openshift-infra:hawkular-metrics:metrics-hawkular-metrics:$openshift_metrics_image_version openshift-infra:heapster:metrics-heapster:$openshift_metrics_image_version"
  else
    pod_check_string="'registry|router'|egrep -v '^\$| SUCCESS '"        
  fi

  #check images
  for objFullSpec in $objFullSpecList; do
    objSpec=$(echo "$objFullSpec"|cut -f1-2 -d:|tr ':' ' ')
    imageSpec=$(echo "$objFullSpec"|cut -f3 -d:)
    imageTag=$(echo "$objFullSpec"|cut -f4 -d:)

    #echo "DFW HERE 7.1 objSpec ==>$objSpec<=="
    #echo "DFW HERE 7.2 imageSpec ==>$imageSpec<=="
    #echo "DFW HERE 7.3 imageTag ==>$imageTag<=="
    
    if ! (ansible masters[0] -i ${hosts_file} -m shell -a \
     "oc get -n $objSpec -o jsonpath='{.spec.template.spec.containers[*].image}'|egrep \"${imageSpec}:${imageTag}\""); then
      if [ "$imageSpec" = "registry-console" ]; then
        # Check for "v<ocp_ver_major>.<ocp_ver_minor>" ("v3.9")
        imageTag=$(echo "$imageTag"|cut -f1-2 -d.)
        if ! (ansible masters[0] -i ${hosts_file} -m shell -a \
         "oc get -n $objSpec -o jsonpath='{.spec.template.spec.containers[*].image}'|egrep \"${imageSpec}:${imageTag}\""); then
          usageExit 201 $hosts_file $FUNCNAME "Failed to verify Image for $objSpec"
        fi
      else
        usageExit 201 $hosts_file $FUNCNAME "Failed to verify Image for $objSpec"
      fi
    fi
  done

  #check pods
  checkPods=$(ansible masters[0] -i ${hosts_file} -m shell -a "oc get pod --all-namespaces"|eval egrep $pod_check_string | awk '{print $1,$2}'|tr ' ' ':')
  
  #echo "DFW HERE 15.1 checkPods ==>${checkPods}<==" 
  #echo "DFW HERE 17.1 podSpecList ==>${podSpecList}<==" 
  for podSpec in $podSpecList; do
    pod_ns=$(echo "$podSpec"|cut -f1 -d:)
    pod_name=$(echo "$podSpec"|cut -f2 -d:)
    imageSpec=$(echo "$podSpec"|cut -f3 -d:)
    imageTag=$(echo "$podSpec"|cut -f4 -d:)

    #echo "DFW HERE 16.1 pod_ns ==>${pod_ns}<=="
    #echo "DFW HERE 16.2 pod_name ==>${pod_name}<=="
    #echo "DFW HERE 16.3 imageSpec ==>${imageSpec}<=="
    #echo "DFW HERE 16.4 imageTag ==>${imageTag}<=="

    #nsPod=$(echo $checkPods|tr ' ' '\n'|egrep "$pod_ns:$pod_name"|tr ':' ' ')
    echo $checkPods|tr ' ' '\n'|egrep "$pod_ns:$pod_name"|tr ':' ' '|while read nsPod; do
      #echo "DFW HERE 16.5 nsPod ==>${nsPod}<=="
    
      if ! (ansible masters[0] -i ${hosts_file} -m shell  -a "oc get pod -n $nsPod -o \
       jsonpath='{.spec.containers[*].image}'|egrep \"${imageSpec}:${imageTag}\""); then
          usageExit 202 $hosts_file $FUNCNAME "Failed to verify image, in pod, for $pod_name"
      fi
    done
  done
}

function post_create_role_rules_details_file() {
  local role_rules_yaml_file=$1
  local role_rules_descr_file=$2
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  tail -$(echo $[$(wc -l $role_rules_yaml_file|awk '{print $1}')-$(grep -n rules: $role_rules_yaml_file|cut -f1 -d:)]) $role_rules_yaml_file |\
   python -c 'import sys, yaml, json; json.dump(yaml.load(sys.stdin), sys.stdout, indent=4)' > $tmpFile3

  res_size=$(for i in $(seq 0 1 $(cat $tmpFile3 |python -c "import sys, json; print len(json.load(sys.stdin))-1")); do
    res_api_groups=$(cat $tmpFile3 |python -c "import sys, json; json.dump(json.load(sys.stdin)[$i]['apiGroups'],sys.stdout, indent=4)" 2>/dev/null|egrep -v '(\[|\])$'|cut -f2 -d'"')
    res_names=$(cat $tmpFile3|python -c "import sys, json; json.dump(json.load(sys.stdin)[$i]['resources'],sys.stdout, indent=4)"  2>/dev/null|egrep -v '(\[|\])$'|cut -f2 -d'"')
    if [ ! -z "$res_names" ]; then
      for res_name in $res_names; do
        if [ -z "$res_api_groups" ]; then
          echo "$res_name"|wc -c
        else
          if (echo $res_name|egrep -q '/'); then
            res_name_pre=$(echo "$res_name"|cut -f1 -d/)
            res_name_suff=$(echo "$res_name"|cut -f2- -d/)
            echo "${res_name_pre}.${res_api_groups}/${res_name_suff}" |wc -c
          else
            echo "${res_name}.${res_api_groups}" |wc -c
          fi
        fi
      done
    fi
  done|sort -n |tail -1)

  for i in $(seq 0 1 $(cat $tmpFile3 |python -c "import sys, json; print len(json.load(sys.stdin))-1")); do
    res_api_groups=$(cat $tmpFile3 |python -c "import sys, json; json.dump(json.load(sys.stdin)[$i]['apiGroups'],sys.stdout, indent=4)" 2>/dev/null|egrep -v '(\[|\])$'|cut -f2 -d'"')
    res_names=$(cat $tmpFile3|python -c "import sys, json; json.dump(json.load(sys.stdin)[$i]['resources'],sys.stdout, indent=4)" 2>/dev/null|egrep -v '(\[|\])$'|cut -f2 -d'"')
    res_verbs=$(cat $tmpFile3|python -c "import sys, json; json.dump(json.load(sys.stdin)[$i]['verbs'],sys.stdout, indent=4)"|egrep -v '(\[|\])$'|cut -f2 -d'"'|sort|tr '\n' ' '|sed 's/ $//')
    if [ -z "$res_names" ]; then
      res_nonResourceURLs=$(cat $tmpFile3|python -c "import sys, json; json.dump(json.load(sys.stdin)[$i]['nonResourceURLs'],sys.stdout, indent=4)"|egrep -v '(\[|\])$'|cut -f2 -d'"'|tr '\n' ' '|sed 's/ $//')
      printf "  %-${res_size}s %-18s %-15s [%s]\n" ' ' "[$res_nonResourceURLs]" '[]' "${res_verbs}"
    else
      for res_name in $res_names; do
        if [ -z "$res_api_groups" ]; then
          printf "  %-${res_size}s %-18s %-15s [%s]\n" $res_name '[]' '[]' "${res_verbs}"
        else
          if (echo $res_name|egrep -q '/'); then
            res_name_pre=$(echo "$res_name"|cut -f1 -d/)
            res_name_suff=$(echo "$res_name"|cut -f2- -d/)
            printf "  %-${res_size}s %-18s %-15s [%s]\n" "${res_name_pre}.${res_api_groups}/${res_name_suff}" '[]' '[]' "${res_verbs}"
          else
            printf "  %-${res_size}s %-18s %-15s [%s]\n" "${res_name}.${res_api_groups}" '[]' '[]' "${res_verbs}"
          fi
        fi
      done
    fi
  done|sort -u > $role_rules_descr_file

  declare -A clust_res_verbs
  declare -A clust_res_urls
  clust_res_verbs=()
  clust_res_urls=()

  for u_line in $(cat $role_rules_descr_file | tr -s ' '|tr ' ' '|'); do
    line=$(echo "$u_line"|tr '|' ' ')
    res_name=$(echo "$line" | cut -f1 -d'['|tr -d ' ')
    if [ -z "$res_name" ]; then
      res_name="NULL"
    fi
    res_nonResourceURLs=$(echo "$line"| cut -f2 -d'['|cut -f1 -d']')
    res_names=$(echo "$line"| cut -f3 -d'['|cut -f1 -d']')
    res_verbs=$(echo "$line"| cut -f4 -d'['|cut -f1 -d']')

    clust_res_verbs["${res_name}"]="${clust_res_verbs["${res_name}"]} $res_verbs"
    clust_res_urls["${res_name}"]="${clust_res_urls["${res_name}"]} $res_nonResourceURLs"
  done
  cat /dev/null > $tmpFile3
  for res_name in "${!clust_res_verbs[@]}"; do
    if [ "$res_name" != "NULL" ];then
      printf "  %-${res_size}s %-18s %-15s [%s]\n" $res_name '[]' '[]' "$(echo "${clust_res_verbs["$res_name"]}"|sed 's/^ //g')" >> $tmpFile3
    fi
  done

  cat /dev/null > $role_rules_descr_file
  if [ ! -z "${clust_res_urls["NULL"]}" ]; then
    printf "  %-${res_size}s %-18s %-15s [%s]\n" ' ' "[$(echo "${clust_res_urls["NULL"]}]"|sed 's/^ //g')" '[]' "$(echo "${clust_res_verbs["NULL"]}"|sed 's/^ //g')" >> $role_rules_descr_file
  fi
  sort $tmpFile3 >> $role_rules_descr_file
}


function post_verify_rsyslog_still_logging() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ansible all -i ${hosts_file} -a "logger -p local6.info \"Test rsyslog logging after OCP Upgrade of $ocp_version\"" 1>/dev/null 2>&1
  if ! (ansible all -i ${hosts_file} -m shell -a "grep \"Test rsyslog logging after OCP Upgrade of $ocp_version\" /var/log/messages|grep -v ansible-command"); then
    usageExit 203 $hosts_file $FUNCNAME "Failed to verify rsyslog logging after $ocp_version OCP Upgrade"
  fi
}


function post_verify_integrated_registry_resolves() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  
  # Get ClusterIP for docker-registry service
  docker_registry_ip=$(ansible masters[0] -i ${hosts_file} -a "oc get svc -n default docker-registry -o jsonpath='{.spec.clusterIP}'"| grep -v ' SUCCESS ')

  # Use a simple "decimal dotted" regular expression check (not testing if octet > 254)
  if ! (echo $docker_registry_ip | egrep -q '[0-9]\.[0-9]+\.[0-9]+\.[0-9]'); then
    usageExit 87 $hosts_file $FUNCNAME "Failed to get docker-registry service's Cluster IP, got '$docker_registry_ip' "
  fi

  #Loop through the nodes that can't resolve docker-registry.default.svc, and restart NetworkManager
  for node in $(ansible all -i ${hosts_file} -m shell -a "getent hosts docker-registry.default.svc |cut -f1 -d' '|grep -q $docker_registry_ip"|egrep 'FAILED'|awk '{print $1}'); do
    echo  "Restarting NetworkManager on $node"
    if ! (ansible -i ${hosts_file} $node -m systemd -a 'name=NetworkManager enabled=True state=restarted'); then
        usageExit 88 $hosts_file $FUNCNAME echo "Failed to restart NetworkManager on $node"
    fi

    #Fail, if node still can't resolve docker-registry.default.svc (after restarting NetworkManager)
    if ! (ansible -i ${hosts_file} $node -m shell -a "getent hosts docker-registry.default.svc |cut -f1 -d' '|grep -q $docker_registry_ip" >/dev/null 2>&1);  then
         usageExit 89 $hosts_file $FUNCNAME "Failed to resolve 'docker-registry.default.svc' on $node"
    fi
  done

}

function post_restore_yum_repo() {
  local hosts_file=$1
  echo -e "\n\n\t\t**** In Function '\033[7m\033[35m${FUNCNAME}\033[0m' at $(date  +"%m/%d/%y %H:%M:%S") ($(date +"%s"))****"
  ans_output=$(ansible-playbook -i ${hosts_file} custom-openshift-ansible/playbooks/ocp-upgrade-prep.yml \
     -e restore_yum_repo=true; echo $?)
  if !  (echo $ans_output|egrep -q " 0$"); then
    usageExit 246 $hosts_file $FUNCNAME "$ans_output"
  else
    echo "Restored yum repo"
  fi
}







# Main
start_epoch_sec=$(date +"%s")
tmpFile1=/tmp/upgrade_ocp_$$_1.tmp
tmpFile2=/tmp/upgrade_ocp_$$_2.tmp
tmpFile3=/tmp/upgrade_ocp_$$_3.tmp
while getopts ":i:m:l:c:n:g:b:e:h:" option; do
  case "${option}" in
    i)
        hosts_file=${OPTARG}
        ;;
    l)
        log_file=${OPTARG}
        ;;
    #check-hosts-file)
    c)
        check_hosts=${OPTARG}
        ;;
    m)
        method=${OPTARG}
        ;;
    g)
        ans_host_group=${OPTARG}
        ;;
    b)
        begin_node=${OPTARG}
        ;;
    e)
        end_node=${OPTARG}
        ;;
    n)
        nodes_serial=${OPTARG}
        ;;
    h)
        single_host=${OPTARG}
        ;;
    *)
        usageExit 1
        ;;
  esac
done
shift $((OPTIND-1))

#echo "DFW HERE 3 nodes_serial  ==>${nodes_serial}<=="
if [ -z "$hosts_file" ]; then
  usageExit 3
elif [ ! -f "$hosts_file" ]; then
  usageExit 4 $hosts_file
elif [ ! -z "$check_hosts" ]; then
  case "$method" in
    prep_verify_ansible_hosts|upgrade_control_plane|upgrade_infra_nodes|upgrade_app_nodes|upgrade_metrics|upgrade_all|fix_remove_label_from_nodes_in_range|fix_schedule_nodes_in_range|fix_remove_label_from_all_nodes|fix_schedule_all_nodes|fix_rsyslog_logging|post_verify_router_registry_and_metrics_pods|post_verify_integrated_registry_resolves|post_verify_rsyslog_still_logging|post_restore_yum_repo|post_prometheus_cluster_monitoring)
      if ! (ansible -i ${hosts_file} all -m ping 1>/dev/null 2>&1); then 
        usageExit 5 $hosts_file
      fi
      ;;
    *)
      usageExit 2
      ;;
  esac
fi
if [ -z "$log_file" ]; then
  log_file=/tmp/ocp_upgrade.log
fi
if [ ! -z "$ans_host_group" ]; then
  #if [ "$ans_host_group" = "masters" -o "$ans_host_group" = "infra-nodes" -o "$ans_host_group" = "app-nodes" ]; 
  if (ansible -i ${hosts_file} ${ans_host_group} --list-hosts 2>/dev/null| egrep -q 'hosts \(0\)');  then 
    # Get 'groups' JSON via ansible 
     ans_groups_json="{$(ansible all[0] -i $hosts_file -m debug -a "var=groups"|grep -v 'SUCCESS' )"

    # Extract group names via python
    ans_groups_avail=$(echo $ans_groups_json |python -c "import sys, json; print json.load(sys.stdin)['groups'].keys()"|tr ',' '\n' |cut -f2 -d"'"|sort|grep -v '^ungrouped$'|tr '\n' ' ')
    usageExit 8 $hosts_file $ans_host_group "$ans_groups_avail"
  fi
fi

#Set playbook vars, based on OCP version
upgrade_metrics_playbook=/usr/share/ansible/openshift-ansible/playbooks/openshift-metrics/config.yml 
openshift_image_tag=$(egrep "^(o|\s+o)penshift_image_tag" ${hosts_file}|cut -f2 -d=)
openshift_metrics_image_version=$(egrep "^(o|\s+o)penshift_metrics_image_version" ${hosts_file}|cut -f2 -d=)
openshift_metrics_install_metrics=$(egrep "^(o|\s+o)penshift_metrics_install_metrics" ${hosts_file}|cut -f2 -d=|tr '[A-Z]' '[a-z]')
openshift_release=$(egrep "^(o|\s+o)penshift_release" ${hosts_file}|cut -f2 -d=)
ocp_version=$(echo $openshift_release | tr -d 'v')
yum_repo_ver=$(echo $ocp_version | tr -d '.')
playbook_dir=$(echo $openshift_release | tr '.' '_')

cluster_env=$(basename ${hosts_file}|cut -d_ -f2)

upgrade_control_plane_playbook=/usr/share/ansible/openshift-ansible/playbooks/byo/openshift-cluster/upgrades/${playbook_dir}/upgrade_control_plane.yml 
upgrade_node_playbook=/usr/share/ansible/openshift-ansible/playbooks/byo/openshift-cluster/upgrades/${playbook_dir}/upgrade_nodes.yml



# Check if the version for 'openshift_release' in ansible hosts inventory file matches openshift-ansible package version
openshift_ansible_ver=$(rpm -qa | grep openshift-ansible-3|cut -d- -f3|cut -f1-2 -d'.')

# DFW - use for testing clusters at diff ver
#openshift_ansible_ver=3.11



if [ "$ocp_version" != "$openshift_ansible_ver" ]; then 
  usageExit 7 $hosts_file $ocp_version $openshift_ansible_ver
fi




case "$method" in
  upgrade_all)
       upgrade_control_plane $hosts_file
       upgrade_infra_nodes $hosts_file
       upgrade_app_nodes $hosts_file
       if [ "$openshift_metrics_install_metrics" = "true" ]; then 
         upgrade_metrics $hosts_file
       fi
       ;;
  upgrade_control_plane|upgrade_infra_nodes|upgrade_app_nodes|upgrade_metrics)
       $method $hosts_file  
       ;;
  fix_remove_label_from_nodes_in_range|fix_schedule_nodes_in_range|fix_remove_label_from_all_nodes|fix_schedule_all_nodes)
       $method $hosts_file  
       ;;
  fix_rsyslog_logging)
       if [ -z "$single_host" ]; then
         usageExit 50
       fi
       $method $hosts_file $single_host
       ;;
  prep_verify_ansible_hosts|prep_configure_docker|prep_pull_docker_images|prep_verify_sbin_in_path|prep_fix_openshift_ansible_playbook\
   |prep_test_conn_local_yum_repo|prep_local_yum_repo|prep_verify_local_yum_repo\
   |prep_clean_old_etcd_backup|prep_verify_local_file_systems|prep_backup\
   |prep_install_excluder_packages|prep_create_node_configmaps\
   |prep_prometheus_cluster_monitoring|prep_fix_cassandra_rc_node_selector|prep_set_hostname_to_fqdn)
       $method $hosts_file  
       ;;
  post_verify_router_registry_and_metrics_pods|post_verify_integrated_registry_resolves|post_verify_rsyslog_still_logging|post_restore_yum_repo\
   |post_prometheus_cluster_monitoring)
       $method $hosts_file  
       ;;
  *)
       usageExit 2
       ;;
esac

# Clean up tmp file
#[ -f $tmpFile1 ] && (rm -f $tmpFile1)
#[ -f $tmpFile2 ] && (rm -f $tmpFile2)
#[ -f $tmpFile3 ] && (rm -f $tmpFile3)

stop_epoch_sec=$(date +"%s")
elapsed_sec=$[$stop_epoch_sec-$start_epoch_sec]
elapsed_time=$(if [ "$elapsed_sec" -lt "3600" ]; then
   printf "%d:%s\n" $[$elapsed_sec/60] $(printf '%2.0d' $[$elapsed_sec-$[$(echo $[$elapsed_sec/60])*60]]|sed 's/  /00/'|sed 's/ /0/')
else
  elapsed_sec_r=$(echo "$[$elapsed_sec-$[$(echo $[$elapsed_sec/3600])*3600]]")
  printf "%d:%s:%s\n" $[$elapsed_sec/3600] $(printf '%2.0d' $[$elapsed_sec_r/60]|sed 's/  /00/'|sed 's/ /0/') $(printf '%2.0d' $[$elapsed_sec_r-$[$(echo $[$elapsed_sec_r/60])*60]]|sed 's/  /00/'|sed 's/ /0/')
fi)
echo "$0 completed in $elapsed_time ($elapsed_sec seconds)"



