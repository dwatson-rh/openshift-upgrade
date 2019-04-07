#!/bin/bash

if [ "$#" != "0" ] && [ "$1" = "auto" ]; then
  # "Auto" mode
  start_epoch_sec=$(date +"%s")

  # Check if the version for 'openshift_pkg_version' in ansible hosts inventory file matches openshift-ansible package version
  openshift_pkg_version=$(egrep "^(o|\s+o)penshift_pkg_versio(n=|n\s=)" $2|cut -f2 -d=|tr -d '-'|cut -f1-2 -d'.')
  openshift_ansible_ver=$(rpm -qa | grep openshift-ansible-3|cut -d- -f3|cut -f1-2 -d'.')

  if [ "$openshift_pkg_version" != "$openshift_ansible_ver" ]; then
    echo "The openshift_pkg_version (major.minor), $openshift_pkg_version, in hosts file, $2, does NOT match the openshift-ansible package version, $openshift_ansible_ver"
    exit 8
  fi

  ./upgrade_ocp.sh -i $2 -check-hosts-file -m prep_verify_ansible_hosts
  return_status=$?
  if [ "$return_status" != "0" ]; then
    echo "Cannot verify hosts file, failed with return code: $return_status"
    exit $return_status
  fi

  methods_in_ocp_ver=""
  if [ "$openshift_pkg_version" = "3.11" ]; then
    for method_in_ocp_ver in                        \
      XXXXprep_configure_docker                         \
      prep_pull_docker_images                       \
      prep_verify_sbin_in_path                      \
      prep_fix_openshift_ansible_playbook           \
      prep_test_conn_local_yum_repo                 \
      prep_local_yum_repo                           \
      prep_verify_local_yum_repo                    \
      XXXXprep_clean_old_etcd_backup                    \
      prep_verify_local_file_systems                \
      prep_backup                                   \
      prep_install_excluder_packages                \
      XXXXprep_create_node_configmaps                   \
      XXXXprep_set_hostname_to_fqdn                     \
      upgrade_all                                   \
      XXXXprep_fix_cassandra_rc_node_selector           \
      post_verify_router_registry_and_metrics_pods  \
      XXXXpost_verify_integrated_registry_resolves      \
      post_verify_rsyslog_still_logging             \
      post_restore_yum_repo                         
    do
        methods_in_ocp_ver="$methods_in_ocp_ver $method_in_ocp_ver"
    done
  else
    # For 3.10, or 3.9
    for method_in_ocp_ver in                        \
      XXXXprep_configure_docker                         \
      prep_pull_docker_images                       \
      prep_verify_sbin_in_path                      \
      prep_fix_openshift_ansible_playbook           \
      prep_test_conn_local_yum_repo                 \
      prep_local_yum_repo                           \
      prep_verify_local_yum_repo                    \
      prep_clean_old_etcd_backup                    \
      prep_verify_local_file_systems                \
      prep_backup                                   \
      prep_install_excluder_packages                \
      prep_create_node_configmaps                   \
      prep_fix_cassandra_rc_node_selector           \
      prep_set_hostname_to_fqdn                     \
      upgrade_all                                   \
      post_verify_router_registry_and_metrics_pods  \
      post_verify_integrated_registry_resolves      \
      XXXXpost_restore_yum_repo                         \
      post_verify_rsyslog_still_logging             
    do
      methods_in_ocp_ver="$methods_in_ocp_ver $method_in_ocp_ver"
    done
  fi

  for method in $methods_in_ocp_ver; do
    if ( ! echo "$method" | egrep -q '^X'); then
      ./upgrade_ocp.sh  -i $2 -m $method
      return_status=$?
      if [ "$return_status" != "0" ]; then
        echo "The $method method failed with return code: $return_status"
        exit $return_status
      fi
    fi
  done

  stop_epoch_sec=$(date +"%s")
  elapsed_sec=$[$stop_epoch_sec-$start_epoch_sec]
  elapsed_time=$(if [ "$elapsed_sec" -lt "3600" ]; then
     printf "%d:%s\n" $[$elapsed_sec/60] $(printf '%2.0d' $[$elapsed_sec-$[$(echo $[$elapsed_sec/60])*60]]|sed 's/  /00/'|sed 's/ /0/')
  else
    elapsed_sec_r=$(echo "$[$elapsed_sec-$[$(echo $[$elapsed_sec/3600])*3600]]")
    printf "%d:%s:%s\n" $[$elapsed_sec/3600] $(printf '%2.0d' $[$elapsed_sec_r/60]|sed 's/  /00/'|sed 's/ /0/') $(printf '%2.0d' $[$elapsed_sec_r-$[$(echo $[$elapsed_sec_r/60])*60]]|sed 's/  /00/'|sed 's/ /0/')
  fi)
  echo "$0 completed in $elapsed_time ($elapsed_sec seconds)"

else
  # "Interactive" mode
  /bin/bash
fi

