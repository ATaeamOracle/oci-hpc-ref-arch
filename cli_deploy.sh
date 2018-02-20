#!/bin/bash
#SET TENANCY
export CNODES=2
export C=$1
export PRE=`uuidgen | cut -c-5`
export AD=kWVD:PHX-AD-1
export OS=ocid1.image.oc1.phx.aaaaaaaav4gjc4l232wx5g5drypbuiu375lemgdgnc7zg2wrdfmmtbtyrc5q #OracleLinux
#wget https://raw.githubusercontent.com/tanewill/oci_hpc/master/bm_configure.sh

#LIST OS OCID's
#oci compute image list -c $C --output table --query "data [*].{ImageName:\"display-name\", OCID:id}"

#CREATE NETWORK
echo
echo 'Creating Network'
V=`oci network vcn create --cidr-block 10.0.0.0/24 --compartment-id $C --display-name "hpc_vcn-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
NG=`oci network internet-gateway create -c $C --vcn-id $V --is-enabled TRUE --display-name "hpc_ng-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
RT=`oci network route-table create -c $C --vcn-id $V --display-name "hpc_rt-$PRE" --wait-for-state AVAILABLE --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$NG'"}]' | jq -r '.data.id'`
SL=`oci network security-list create -c $C --vcn-id $V --display-name "hpc_sl-$PRE" --wait-for-state AVAILABLE --egress-security-rules '[{"destination":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' --ingress-security-rules '[{"source":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' | jq -r '.data.id'`
S=`oci network subnet create -c $C --vcn-id $V --availability-domain "$AD" --display-name "hpc_subnet_$AD-$PRE" --cidr-block "10.0.0.0/26" --route-table-id $RT --security-list-ids '["'$SL'"]' --wait-for-state AVAILABLE | jq -r '.data.id'`

#CREATE HEADNODE
echo
echo 'Creating Headnode'
oci compute instance launch --availability-domain "$AD" -c $C --shape "BM.DenseIO2.52" --display-name "hpc_master" --image-id $OS --subnet-id $S --private-ip 10.0.0.2 --wait-for-state RUNNING --user-data-file bm_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub
#for iid in `oci compute instance list -c $C | jq -r '.data[] | select(."lifecycle-state"=="RUNNING") | .id'`; do newip=`oci compute instance list-vnics --instance-id $iid | jq -r '.data[0] | ."display-name"+": "+."private-ip"+", "+."public-ip"'`; echo $iid, $newip; done

#CREATE COMPUTE
echo
echo 'Creating Compute Nodes'
for i in `seq 1 $CNODES`; do oci compute instance launch --availability-domain "$AD" -c $C --shape "BM.DenseIO2.52" --display-name "hpc_cn$i-$PRE" --image-id $OS --subnet-id $S --user-data-file bm_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub; done 

#LIST IP's
echo
echo 'Waiting three minutes for IP addresses'
sleep 180
for iid in `oci compute instance list -c $C | jq -r '.data[] | select(."lifecycle-state"=="RUNNING") | .id'`; do newip=`oci compute instance list-vnics --instance-id $iid | jq -r '.data[0] | ."display-name"+": "+."private-ip"+", "+."public-ip"'`; echo $iid, $newip; done


#DELETE INSTANCES
#for iid in `oci compute instance list -c $C | jq -r '.data[] | select(."lifecycle-state"=="RUNNING") | .id'`; do oci compute instance terminate --instance-id $iid --force; done
#oci network subnet delete --subnet-id $S --force
#oci network route-table delete --rt-id $RT --force
#oci network security-list delete --security-list-id $SL --force
#oci network vcn delete --vcn-id $V --force

