#!/bin/sh
nvmes=`ls -ltr /dev/disk/by-id/ | grep nvme-Amazon_EC2_NVMe_Instance_Storage_ | awk -F'/' '{ print $3 }' | sort -u`
disk="/dev/`echo $nvmes | awk '{ print $1 }'`"
if $1 ; then
    disk="/dev/md0"
    echo "NVME Found: ${nvmes}"
    raid_device=""
    count=0
    for line in `echo $nvmes | tr " " "\n"`; do
        count=$((count + 1))
        if [[ $(sudo /sbin/sfdisk -d /dev/${line}) -eq 0 ]]; then
            raid_device=`echo "$raid_device" " /dev/${line}"`
        else
            echo NVME $line is with Partition exiting
            exit 1
        fi
    done
    echo "Going to Create Raid:\nCMD:mdadm --create --verbose ${disk} --level=0 --raid-devices=${count} ${raid_device}"
    sudo mdadm --create --verbose ${disk} --level=0 --raid-devices=${count} ${raid_device}
    sudo mkfs.xfs -K -f ${disk}
else
    sudo mkfs.xfs -K -f ${disk}
fi
sudo mkdir -p /data
sudo mount ${disk} /data
sudo chmod -R 777 /data
