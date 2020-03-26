#!/bin/bash -x

export KDBUSER=ec2-user
export USERHOME=/home/ec2-user

# pull latest code
cd /opt/rdb-autoscaling
git pull
cd

# configure aws cli
AZ=$(ec2-metadata -z | cut -d ' ' -f 2)
echo -e "[default]\nregion=${AZ::-1}\noutput=json" > ${USERHOME}/.aws/config
chown -R ec2-user:ec2-user ${USERHOME}/.aws

# get instance details
echo -e "source /opt/rdb-autoscaling/aws/ec2-utils.sh\n" >> ${USERHOME}/.bash_profile

export INSTANCEID=$(ec2-metadata -i | cut -d ' ' -f 2)
export APP=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID APP)
export EFS=$(sudo -i -u ec2-user ec2_get_instance_tag $INSTANCEID EFS)

# send to bash profile
echo "export INSTANCEID=$INSTANCEID" >> ${USERHOME}/.bash_profile
echo "export APP=$APP" >> ${USERHOME}/.bash_profile
echo "export EFS=$EFS" >> ${USERHOME}/.bash_profile
echo "" >> ${USERHOME}/.bash_profile

# set up efs
source /opt/rdb-autoscaling/aws/ec2-utils.sh
ec2_mount_efs $EFS /mnt/efs

# start app
sudo -i -u $KDBUSER /opt/rdb-autoscaling/bin/startq --app $APP --log-dir /mnt/efs/logs
