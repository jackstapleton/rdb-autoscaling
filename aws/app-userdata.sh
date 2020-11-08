#!/bin/bash -x

export KDBUSER=ec2-user
export USERHOME=/home/ec2-user

# use develop code
cd /opt/rdb-autoscaling
git pull
git fetch
git checkout demo
cd

# configure aws cli
AZ=$(ec2-metadata -z | cut -d ' ' -f 2)
echo -e "[default]\nregion=${AZ::-1}\noutput=json" > ${USERHOME}/.aws/config
chown -R ec2-user:ec2-user ${USERHOME}/.aws

# get instance details
echo -e "source /opt/rdb-autoscaling/aws/ec2-utils.sh\n" >> ${USERHOME}/.bash_profile

export INSTANCEID=$(ec2-metadata -i | cut -d ' ' -f 2)
export APP=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID APP)
export SCALETHRESHOLD=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID SCALETHRESHOLD)
export ROLLTHRESHOLD=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID ROLLTHRESHOLD)
export STACK=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID aws:cloudformation:stack-name)

while [[ "$TPHOST" == "" ]]; do
    echo "Looking for tick-asg private ip address"
    export TPHOST=$(sudo -i -u ec2-user ec2_get_ip_by_stack_app $STACK tick-asg)
done

# send envvars to bash profile
echo "export INSTANCEID=$INSTANCEID" >> ${USERHOME}/.bash_profile
echo "export APP=$APP" >> ${USERHOME}/.bash_profile
echo "export SCALETHRESHOLD=$SCALETHRESHOLD" >> ${USERHOME}/.bash_profile
echo "export ROLLTHRESHOLD=$ROLLTHRESHOLD" >> ${USERHOME}/.bash_profile
echo "export STACK=$STACK" >> ${USERHOME}/.bash_profile
echo "export TPHOST=$TPHOST" >> ${USERHOME}/.bash_profile
echo "" >> ${USERHOME}/.bash_profile

# add time to ec2 instance name
NAME=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID Name)
ASG=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID aws:autoscaling:groupName)
NUM=$(sudo -i -u ec2-user asg_get_desired_capacity $ASG)
NEWNAME=${NAME}-${NUM}-$(sudo -i -u ec2-user date +%Y%m%dD%H%M%S)
sudo -i -u $KDBUSER aws ec2 create-tags --resources $INSTANCEID --tags Key=Name,Value=$NEWNAME

# start app if its an rdb

if [[ "$app" == "r-asg" ]] ; then
    sudo -i -u $KDBUSER /opt/rdb-autoscaling/bin/startq --app $APP --log-dir /opt/rdb-autoscaling/logs
fi
