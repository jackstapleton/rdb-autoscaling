#!/bin/bash

ec2_get_instance_tag () {
    instance_id=$1
    tag=$2
    until [[ -s $HOME/.ec2-tagdata ]]; do
        aws ec2 describe-tags --filter "Name=resource-id,Values=$instance_id" > $HOME/.ec2-tagdata
    done
    cat $HOME/.ec2-tagdata | python -c "import sys, json; print(''.join([x['Value'] for x in json.load(sys.stdin)['Tags'] if x ['Key'] == '$tag']))"
}

ec2_get_ip_by_stack_app () {
    stack=$1
    app=$2

    res=$(aws ec2 describe-instances \
        --filters Name=tag:aws:cloudformation:stack-name,Values=$stack Name=tag:APP,Values=$app \
        --query "Reservations[*].Instances[*].{PrivateIpAddress:PrivateIpAddress}")

    echo $res | python -c "import sys, json; print(([x[0]['PrivateIpAddress'] for x in json.load(sys.stdin) if not x[0]['PrivateIpAddress'] is None])[0])"
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

asg_get_desired_capacity () {
    asg=$1
    res=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name $ASG)
    echo $res | python -c "import json, sys; print(json.load(sys.stdin)['AutoScalingGroups'][0]['DesiredCapacity'])"
}
