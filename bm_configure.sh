#!/bin/bash

set +x
#set -xeuo pipefail

if [[ $(id -u) -ne 0 ]] ; then
    echo "Must be run as root"
    exit 1
fi

MASTER_HOSTNAME=hpc_master

systemctl stop firewalld
systemctl disable firewalld

# Hpc User
HPC_USER=hpc_user
HPC_UID=7007
HPC_GROUP=hpc
HPC_GID=7007


# Shares
SHARE_NFS=/share/nfs
SHARE_HOME=$SHARE_NFS/home
SHARE_DATA=$SHARE_NFS/data

# Returns 0 if this node is the master node.
#
is_master()
{
    hostname | grep $MASTER_HOSTNAME
    return $?
}

install_pkgs()
{
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    rpm -ivh epel-release-latest-7.noarch.rpm

    mkdir /tmp/intel
    cd /tmp/intel
    wget https://objectstorage.us-phoenix-1.oraclecloud.com/p/7BR1vkeBqaxr1ot0jNSbpQumqdqSFXEhLf1HR1YLJEc/n/hpc/b/HPC_BENCHMARKS/o/intel_mpi_2018.1.163.tgz -O - | tar zx
    ./install.sh --silent=silent.cfg

    impi_version=`ls /opt/intel/impi`
    source /opt/intel/impi/${impi_version}/bin64/mpivars.sh
    ln -s /opt/intel/impi/${impi_version}/intel64/bin/ /opt/intel/impi/${impi_version}/bin
    ln -s /opt/intel/impi/${impi_version}/lib64/ /opt/intel/impi/${impi_version}/lib

    yum repolist
    yum check-update
    yum install -y -q pdsh stress axel fontconfig freetype freetype-devel fontconfig-devel libstdc++ libXext libXt libXrender-devel.x86_64 libXrender.x86_64 mesa-libGL.x86_64 openmpi screen 
    yum install -y -q nfs-utils sshpass nmap htop pdsh screen git psmisc axel
    yum install -y -q gcc libffi-devel python-devel openssl-devel
    yum group install -y -q "X Window System"
    yum group install -y -q "Development Tools"
}
setup_shares()
{
    mkdir -p $SHARE_HOME
    mkdir -p $SHARE_DATA

    if is_master; then
        echo "10.0.0.2    *(rw,async)" >> /etc/exports
        systemctl enable rpcbind || echo "Already enabled"
        systemctl enable nfs-server || echo "Already enabled"
        systemctl start rpcbind || echo "Already enabled"
        systemctl start nfs-server || echo "Already enabled"

        mount -a
        mount
    else
        # Mount master NFS share
        echo "$MASTER_HOSTNAME:$SHARE_NFS $SHARE_NFS    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
        mount -a
        mount | grep "^master:$SHARE_HOME"
    fi
}
setup_hpc_user()
{
    # disable selinux
    sed -i 's/enforcing/disabled/g' /etc/selinux/config
    setenforce permissive

    groupadd -g $HPC_GID $HPC_GROUP

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

    if is_master; then
        mkdir -p $SHARE_HOME

        useradd -c "HPC User" -g $HPC_GROUP -m -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER

        mkdir -p $SHARE_HOME/$HPC_USER/.ssh

        # Configure public key auth for the HPC user
        ssh-keygen -t rsa -f $SHARE_HOME/$HPC_USER/.ssh/id_rsa -q -P ""
        cat $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub > $SHARE_HOME/$HPC_USER/.ssh/authorized_keys

        echo "Host *" > $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    StrictHostKeyChecking no" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    UserKnownHostsFile /dev/null" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    PasswordAuthentication no" >> $SHARE_HOME/$HPC_USER/.ssh/config

        # Fix .ssh folder ownership
        chown -R $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER

        # Fix permissions
        chmod 700 $SHARE_HOME/$HPC_USER/.ssh
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/config
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
        chmod 600 $SHARE_HOME/$HPC_USER/.ssh/id_rsa
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub

    else
        useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER
    fi
}
config_machine()
{
    cd ~
    git clone https://github.com/tanewill/oci_hpc
    source oci_hpc/disable_ht.sh 0
    IP=`hostname -i`
    localip=`echo $IP | cut --delimiter='.' -f -3`
    myhost=`hostname`
    nmap -p 80 $localip.0/28 | grep $localip | awk '{ print $5 }'> $SHARE_HOME/$HPC_USER/hostfile
    sed '/10.0.0.1/d' $SHARE_HOME/$HPC_USER/hostfile -i

}

install_pkgs
touch ~/packages
setup_shares
touch ~/shares
setup_hpc_user
touch ~/user
config_machine
touch ~/config