#!/bin/bash
#SET TENANCY
export CNODES=2
export C=$1
export PRE=`uuidgen | cut -c-5`
export region=us-ashburn-1
export AD=kWVD:US-ASHBURN-AD-1
export OS=ocid1.image.oc1.phx.aaaaaaaav4gjc4l232wx5g5drypbuiu375lemgdgnc7zg2wrdfmmtbtyrc5q #OracleLinux
export OS=ocid1.image.oc1.iad.aaaaaaaautkmgjebjmwym5i6lvlpqfzlzagvg5szedggdrbp6rcjcso3e4kq
#wget https://raw.githubusercontent.com/tanewill/oci_hpc/master/bm_configure.sh

#LIST OS OCID's
#oci compute image list -c $C --output table --query "data [*].{ImageName:\"display-name\", OCID:id}"

#CREATE NETWORK
echo
echo 'Creating Network'
V=`oci network vcn create --region $region --cidr-block 10.0.0.0/24 --compartment-id $C --display-name "hpc_vcn-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
NG=`oci network internet-gateway create --region $region -c $C --vcn-id $V --is-enabled TRUE --display-name "hpc_ng-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
RT=`oci network route-table create --region $region -c $C --vcn-id $V --display-name "hpc_rt-$PRE" --wait-for-state AVAILABLE --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$NG'"}]' | jq -r '.data.id'`
SL=`oci network security-list create --region $region -c $C --vcn-id $V --display-name "hpc_sl-$PRE" --wait-for-state AVAILABLE --egress-security-rules '[{"destination":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' --ingress-security-rules '[{"source":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' | jq -r '.data.id'`
S=`oci network subnet create -c $C --vcn-id $V --region $region --availability-domain "$AD" --display-name "hpc_subnet-$PRE" --cidr-block "10.0.0.0/26" --route-table-id $RT --security-list-ids '["'$SL'"]' --wait-for-state AVAILABLE | jq -r '.data.id'`

#CREATE HEADNODE
echo
echo 'Creating Headnode'
masterID=`oci compute instance launch --region $region --availability-domain "$AD" -c $C --shape "BM.DenseIO2.52" --display-name "hpc_master" --image-id $OS --subnet-id $S --private-ip 10.0.0.2 --wait-for-state RUNNING --user-data-file hn_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub | jq -r '.data.id'`

#CREATE COMPUTE
echo
echo 'Creating Compute Nodes'
for i in `seq 1 $CNODES`; do oci compute instance launch --region $region --availability-domain "$AD" -c $C --shape "BM.Standard2.52" --display-name "hpc_cn$i-$PRE" --image-id $OS --subnet-id $S --assign-public-ip false --user-data-file hn_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub; done 

#LIST IP's
echo
echo 'Waiting five minutes for IP addresses'
sleep 300

masterIP=$(oci compute instance list-vnics --region $region --instance-id $masterID | jq -r '.data[]."public-ip"')

for iid in `oci compute instance list --region $region -c $C | jq -r '.data[] | select(."lifecycle-state"=="RUNNING") | .id'`; do newip=`oci compute instance list-vnics --region $region --instance-id $iid | jq -r '.data[0] | ."display-name"+": "+."private-ip"+", "+."public-ip"'`; echo $iid, $newip; done

scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa opc@$masterIP:~/.ssh/

#CREATE REMOVE SCRIPT
cat << EOF >> removeCluster.sh
#!/bin/bash
export C=$1
export PRE=$PRE
export region=$region
export AD=$AD
export V=$V
export NG=$NG
export RT=$RT
export SL=$SL
export S=$S

#DELETE INSTANCES
for iid in `oci compute instance list --region us-ashburn-1 -c $C | jq -r '.data[] | select(."display-name" | contains("$PRE")) | .id'`; do oci compute instance terminate --instance-id $iid --force; done
oci network subnet delete --region $region --subnet-id $S --force
oci network route-table delete --region $region --rt-id $RT --force
oci network security-list delete --region $region --security-list-id $SL --force
oci network vcn delete --region $region --vcn-id $V --force
EOF

chmod +x removeCluster.sh