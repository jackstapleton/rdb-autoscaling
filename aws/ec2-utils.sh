#!/bin/bash

ec2_get_instance_tag () {
    instance_id=$1
    tag=$2
    until [[ -s $HOME/.ec2-tagdata ]]; do
        aws ec2 describe-tags --filter "Name=resource-id,Values=$instance_id" > $HOME/.ec2-tagdata
    done
    cat $HOME/.ec2-tagdata | python -c "import sys, json; print(''.join([x['Value'] for x in json.load(sys.stdin)['Tags'] if x ['Key'] == '$tag']))"
}

ec2_mount_efs () {
    efs_ip=$1
    efs_dir=$2
    echo -e "\nMounting the $efs_ip EFS filesystem at $efs_dir\n"
    mkdir -p -m a=rwx $efs_dir
    mount -t nfs $efs_ip:/ $efs_dir
    chmod 777 $efs_dir
    df -h
}
