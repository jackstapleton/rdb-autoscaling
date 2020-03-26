#!/bin/bash -x

export USERHOME=/home/ec2-user

# install yum packages
sudo yum update -y
sudo yum install -y amazon-efs-utils
sudo yum install -y git
sudo yum install -y tmux
sudo yum install -y tree

# set up conda
sudo -i -u ec2-user wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh -O ${USERHOME}/conda.sh
chmod 777 /opt
sudo -i -u ec2-user bash ${USERHOME}/conda.sh -b -p /opt/miniconda
rm ${USERHOME}/conda.sh
echo -e "\nsource /opt/miniconda/etc/profile.d/conda.sh\nconda activate\n" >> ${USERHOME}/.bash_profile
source ${USERHOME}/.bash_profile

# set up kdb
sudo -i -u ec2-user conda install kdb -c kx -y
sudo -i -u ec2-user git clone https://github.com/jackstapleton/rdb-autoscaling.git /opt/rdb-autoscaling

# set up dev env
sudo -i -u ec2-user git clone https://github.com/jackstapleton/environments-setup.git ${USERHOME}/environments-setup
sudo -i -u ec2-user ${USERHOME}/environments-setup/dot-files/util/vim-install.sh

# configure aws cli
mkdir -p ${USERHOME}/.aws
AZ=$(ec2-metadata -z | cut -d ' ' -f 2)
echo -e "[default]\nregion=${AZ::-1}\noutput=json" >> ${USERHOME}/.aws/config
chown -R ec2-user:ec2-user ${USERHOME}/.aws

# create ami
INSTANCEID=$(ec2-metadata -i | cut -d ' ' -f 2)
AMIDATE=$(date +%Y%m%dD%H%M%S)
AMINAME=${AZ::-1}-kdb-ec2.ami-$AMIDATE
sudo -i -u ec2-user aws ec2 create-image --instance-id $INSTANCEID --name $AMINAME
