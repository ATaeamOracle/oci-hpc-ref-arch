#!/bin/bash
MYUSER=opc
MYHOST=10.0.0.2

sudo systemctl stop firewalld
sudo systemctl disable firewalld

wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
rpm -ivh epel-release-latest-7.noarch.rpm

yum repolist
yum check-update
yum install -y -q pdsh stress axel fontconfig freetype freetype-devel fontconfig-devel libstdc++ libXext libXt libXrender-devel.x86_64 libXrender.x86_64 mesa-libGL.x86_64 openmpi screen 
yum install -y -q nfs-utils sshpass nmap htop pdsh screen git psmisc axel
yum install -y -q gcc libffi-devel python-devel openssl-devel
yum group install -y -q "X Window System"
yum group install -y -q "Development Tools"

IP=`hostname -i`
localip=`echo $IP | cut --delimiter='.' -f -3`
myhost=`hostname`
nmap -p 80 $localip.0/28 | grep $localip | awk '{ print $5 }'> /home/$MYUSER/hostfile
sed '/10.0.0.1/d' hostfile -i

cat << EOF >> /etc/security/limits.conf
*               hard    memlock         unlimited
*               soft    memlock         unlimited
*               hard    nofile          65535
*               soft    nofile          65535
EOF

#DISABLE HYPERTHREADING, INSTALL GANGLIA, INSTALL NFS
cd ~
git clone https://github.com/oci-hpc/oci-hpc-ref-arch
source oci-hpc-ref-arch/disable_ht.sh 0
#source oci_hpc/install_ganglia.sh $MYHOST OCI 8649
source oci_hpc/nfs_setup.sh $MYHOST
chown -r $MYUSER:$MYUSER /mnt/share/scratch

#USER CONFIGURATION
mkdir -p /home/$MYUSER/bin
chown $MYUSER:$MYUSER /home/$MYUSER/bin

cat << EOF >> /home/$MYUSER/.bashrc
export WCOLL=/home/$MYUSER/hostfile
export PATH=/opt/intel/compilers_and_libraries_2018.1.163/linux/mpi/intel64/bin:$PATH
export I_MPI_ROOT=/opt/intel/compilers_and_libraries_2018.1.163/linux/mpi
export MPI_ROOT=$I_MPI_ROOT
EOF

chown $MYUSER:$MYUSER /home/$MYUSER/.bashrc

ssh-keygen -f /home/$MYUSER/.ssh/id_rsa -t rsa -N ''
cat << EOF > /home/$MYUSER/.ssh/config
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    PasswordAuthentication no
    LogLevel QUIET
EOF
cat /home/$MYUSER/.ssh/id_rsa.pub >> /home/$MYUSER/.ssh/authorized_keys
chmod 644 /home/$MYUSER/.ssh/config
chown $MYUSER:$MYUSER /home/$MYUSER/.ssh/*

# Don't require password for HPC user sudo
echo "$MYUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# Disable tty requirement for sudo
sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

mkdir /tmp/intel
cd /tmp/intel
wget https://objectstorage.us-phoenix-1.oraclecloud.com/p/7BR1vkeBqaxr1ot0jNSbpQumqdqSFXEhLf1HR1YLJEc/n/hpc/b/HPC_BENCHMARKS/o/intel_mpi_2018.1.163.tgz -O - | tar zx
./install.sh --silent=silent.cfg

impi_version=`ls /opt/intel/impi`
source /opt/intel/impi/${impi_version}/bin64/mpivars.sh
ln -s /opt/intel/impi/${impi_version}/intel64/bin/ /opt/intel/impi/${impi_version}/bin
ln -s /opt/intel/impi/${impi_version}/lib64/ /opt/intel/impi/${impi_version}/lib


:'
wget https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh
chmod +x install.sh
./install.sh --accept-all-defaults
exec -l $SHELL
'