#!/bin/bash
start_epoch_sec=$(date +"%s")

# Check if HOSTS_FILE_310 & HOSTS_FILE_311 are set & have the correct OpenShift version
for minor_ver in 10 11; do
  eval host_env_var=HOSTS_FILE_3${minor_ver}
  eval ans_inv_hosts_file=$(env|grep "^${host_env_var}="|cut -f2 -d=)
  ocp_version="3.${minor_ver}"
  #echo "host_env_var ==>$host_env_var<== ans_inv_hosts_file ==>$ans_inv_hosts_file<== ocp_version ==>$ocp_version<=="
  if [ -z "$ans_inv_hosts_file" ]; then
    echo "Please set $host_env_var"
    exit 17
  else
    if [ -f ../custom-openshift-ansible/${ans_inv_hosts_file} ]; then
      openshift_pkg_version=$(egrep "^(o|\s+o)penshift_pkg_versio(n=|n\s=)" ../custom-openshift-ansible/${ans_inv_hosts_file}|cut -f2 -d=|tr -d '-'|cut -f1-2 -d'.')   
      if [ "$openshift_pkg_version" != "$ocp_version" ]; then
        echo "The openshift_pkg_version (major.minor), $openshift_pkg_version, in the '$host_env_var' hosts file, ../custom-openshift-ansible/${ans_inv_hosts_file}, is NOT '$ocp_version'"
        exit 15
      fi
    else
      echo "Please set $host_env_var to a valid file (can't find '../custom-openshift-ansible/${ans_inv_hosts_file}')"
      exit 16
    fi
  fi
done

# Set UID, if not already set
if [ -z "$UID" ]; then 
  UID="$(id -u)" 
fi
 
time_stamp=$(date +"%m/%d/%y %H:%M:%S" |  sed 's/\///g' | sed 's/ /_/g' | sed 's/://g'|cut -f1 -d.)

# Loop through the 3.10 & 3.11 hosts files and upgrade
for ans_inv_hosts_file in $HOSTS_FILE_310 $HOSTS_FILE_311; do
  openshift_pkg_version=$(egrep "^(o|\s+o)penshift_pkg_versio(n=|n\s=)" ../custom-openshift-ansible/${ans_inv_hosts_file}|cut -f2 -d=|tr -d '-'|cut -f1-2 -d'.')   
  ocp_short_ver=$(echo $openshift_pkg_version | tr -d '.')

  log_file="upgrade_ocp_via_docker_${ocp_short_ver}_${time_stamp}.log"

  
  # Run docker container in 'auto' mode
  sudo docker run --name custom-ose-ansible-${openshift_pkg_version} -u $UID -dit -v $PWD/../custom-openshift-ansible/:/opt/app-root/src/custom-openshift-ansible:Z -v $HOME/.ssh/id_rsa:/opt/app-root/src/.ssh/id_rsa:Z custom-ose-ansible-${openshift_pkg_version} auto custom-openshift-ansible/${ans_inv_hosts_file}

  # Log output of 'auto' mode
  sudo docker logs -f custom-ose-ansible-${openshift_pkg_version}| tee ${log_file}

  if ! (tail -1 ${log_file}|egrep -q 'upgrade_ocp_entrypoint\.sh completed in .* seconds\)'); then 
    echo "Failed to upgrade to version ${openshift_pkg_version}. See ${log_file} for details"
    exit 18
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

