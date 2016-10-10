#!/bin/sh

# make_restore.sh
# 
#
# Created by Daniel Faltin on 25.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

# 
# Globals of make_restore.sh
#
PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/opt/ignite-lx/bin"
export PATH

IGX_BACKEND_MOD=""
IGX_BACKEND_URL=""
IGX_BACKEND_IMG=""
IGX_CONFIGSET_NAME=""
IGX_SYSCONF_FILE=""
IGX_COMMON_INCL="bin/common/ignite_common.inc"
IGX_START_POINT="udev"
IGX_RECOVERY_STEPS="udev modules hostname network init_backend bind_backend mbr raid lvm mkfs mount_fs extract grub"

DISK1="/dev/sda"
DISK2="/dev/sdb"
PART1="/dev/sda1"
PART2="/dev/sdb1"


#
# Panic function start shell in case of error, that means if prev. retval is not equal zero
#
panic()
{
    assert_retval=$?
    
    if [ $assert_retval -ne 0 ]; then
        post_edit "$1"
        if [ $? -ne 0 ]; then
            igx_log " "
            igx_log " "
            igx_log "****************************************************************************"
            igx_log "ERROR: Ignite Step: $1 FAIL!"
            igx_log "Please execute the step manually!"
            igx_log "RUN: \"exit\" to continue with restore!"
            igx_log "Running Recovery Shell!"
            igx_log "****************************************************************************"
            igx_shell
        fi
    fi
    
    return $assert_retval
}

#
# Offer the possiblity of a post setting edit for some steps.
#
post_edit()
{
    case $1 in
   
       network)
          igx_log "****************************************************************************"
          igx_log "ERROR STEP \"$1\" FAILED, PLEASE PRESS ENTER..."
          igx_log "****************************************************************************"
          read key
          net_ret_stat=1
          igx_menu_yesno "Edit network?" && edit_restore.sh "$IGX_CONFIGSET_NAME" 1 && net_ret_stat=0 || return $net_ret_stat
          igx_menu_yesno "Edit routing?" && edit_restore.sh "$IGX_CONFIGSET_NAME" 2 || return $net_ret_stat
       ;;

       mbr) 
          igx_log "An error has occurred while running step \"$1\", please press ENTER to continue..."
          read key
          igx_menu_yesno "Edit boot disks?" && edit_restore.sh "$IGX_CONFIGSET_NAME" 3 || return 1
       ;;

       raid) 
          igx_log "An error has occurred while running step \"$1\", please press ENTER to continue..."
          read key
          igx_menu_yesno "Edit raid?" && edit_restore.sh "$IGX_CONFIGSET_NAME" 5 || return 1
       ;;

       lvm)
          igx_log "An error has occurred while running step \"$1\", please press ENTER to continue..."
          read key
          igx_menu_yesno "Edit lvm pvs?" && edit_restore.sh "$IGX_CONFIGSET_NAME" 4 || return 1
       ;;

       mkfs)
          igx_log "An error has occurred while running step \"$1\", please press ENTER to continue..."
          read key
          igx_menu_yesno "Edit fs devices?" && edit_restore.sh "$IGX_CONFIGSET_NAME" 6 || return 1
       ;;

       *)
           igx_log "No post setting edit for step \"$1\" possible."
           return 1
       ;;

    esac

    return 0
}

#
# Setup script environment and include common functions.
#
if [ -z "$IGX_BASE" ]; then
    IGX_BASE="/opt/ignite-lx"
    export IGX_BASE
fi

if [ -f "$IGX_BASE/$IGX_COMMON_INCL" ]; then
    . "$IGX_BASE/$IGX_COMMON_INCL"
    igx_setenv
    panic "Environment"
    IGX_LOG="ignite_restore.log"
    export IGX_LOG
else
    echo 1>&2 "FATAL: Cannot find major ignite functions $IGX_BASE/$IGX_COMMON_INCL, ABORT!"
    echo 1>&2 "Restore cannot continued with a damaged boot image, calling reboot!"
    sleep 5
    reboot -f 
fi

#
# Usage function parse and check script arguments.
#
usage() 
{
    while getopts "dhvs:" opt; do
        case "$opt" in
            d)
                set -x
            ;;
                        
            s)
                IGX_START_POINT="$OPTARG"
            ;;
            
            v)
                IGX_VERBOSE=1
            ;;
            
            h|*)
                igx_stderr "$IGX_VERSION"
                igx_stderr "usage: make_restore.sh [-dhv -s <start point>] <restore config name>"
                igx_stderr "-h print this screen"
                igx_stderr "-d enable script debug"
                igx_stderr "-v verbose"
                igx_stderr "-s <start point> define the activity point for recovery start"
                igx_stderr ""
                return 1
            ;;
        esac
    done
    
    shift $((OPTIND - 1))
    
    IGX_CONFIGSET_NAME="$@"
    IGX_SYSCONF_FILE="$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/sysconfig.info"
    
    if [ -z "$IGX_CONFIGSET_NAME" ]; then
        igx_stderr "ERROR: Missing recovery configuration set name as argument, ABORT!"
        return 1
    fi
    
    if [ ! -d "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME" ]; then
        igx_stderr "ERROR: Recovery configuration set $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME does not exists, ABORT!"
        return 2
    fi
    
    if [ ! -r "$IGX_SYSCONF_FILE" ]; then
        igx_stderr "ERROR: Cannot access file $IGX_SYSCONF_FILE, ABORT!"
        return 3
    fi
    
    enabled=""
    for step in $IGX_RECOVERY_STEPS; do
        if [ "$IGX_START_POINT" = "$step" ]; then
            enabled="$step"
            continue
        fi
        if [ ! -z "$enabled" ]; then
            enabled="$enabled $step"
        fi
    done
    
    if [ -z "$enabled" ]; then
        igx_stderr "ERROR: The ignite start point $IGX_START_POINT does not exists, ABORT!"
        return 4
    else
        IGX_RECOVERY_STEPS="$enabled"
    fi 
    
    return 0
}

#
# This function load all listed modules in sysconfig.info
#
load_modules()
{
    igx_log "Loading kernel modules..."
    
    awk -F ";" '/^module/ { print $NF; }' "$IGX_SYSCONF_FILE" | while read module; do
        modprobe $module 2> /dev/null && igx_log "Module $module successfuly loaded" || igx_log "Error while loading module $module"
    done
    
    igx_log "Loading of kernel modules done."
    igx_log "Triggering kernel to generate udev events (coldplug)"

    udevadm trigger
    if [ -d /sys/kernel ]; then
        udevadm settle
    fi

    return 0
}

#
# Start/Restart the udev daemon an trigger device scan
#
start_udev()
{
    igx_log "Starting udev daemon"
    
    if [ -d /sys/kernel ]; then
        echo > /sys/kernel/uevent_helper
    else
        igx_log "WARNING: Kernel $(uname -r) does not support inotify, udev will not work!"
        if [ -d /dev_old ]; then
            igx_log "Applying old device nodes (from backup) to /dev mountpoint"
            cd /dev_old && find . -xdev | /bin/cpio -pmdu /dev/
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Failed to copy /dev_old to /dev device root, ABORT!"
                return 1
            fi
        else
            igx_log "FATAL: Cannot applying /dev_old as device root, directory is missing, ABORT!"
            return 2
        fi
    fi
    
    mkdir -p /dev/.udev/db /dev/.udev/queue /dev/.udev/rules.d
    killall udevd 2> /dev/null
    udevd --daemon 
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot run udev daemon, ABORT!"
        return 3
    else
        igx_log "Start of udev daemon done"
        sleep 1
    fi

    igx_log "Triggering kernel to generate udev events (coldplug)"
    udevadm trigger
    if [ -d /sys/kernel ]; then
        udevadm settle
    fi
    
    if [ -d /sys/bus/scsi ]; then
        sleep 1
        modprobe -q scsi_wait_scan && modprobe -r scsi_wait_scan || true
        if [ -d /sys/kernel ]; then
            udevadm settle
        fi
    fi

    return 0
}

#
# Set the local hostname by using $IGX_SYSCONF_FILE
#
restore_hostname()
{
    igx_log "Setting up hostname"
    name="$(awk -F ';' '/^hostname/ { print $NF; }' $IGX_SYSCONF_FILE)"

    if [ -z "$name" ]; then
        igx_log "ERROR: Cannot find hostname in $IGX_SYSCONF_FILE!"
        return 1
    fi
    
    igx_log "Setting hostname to $name"
    hostname "$name"

    return $?
}

restore_network()
{
    igx_log "Configuring network interfaces is not needed"
    return 0
}

#
# Restoring MBR on disk by using $IGX_SYSCONF_FILE
#
restore_mbr()
{
    igx_log "Restoring Master Boot Record(s)"
    
    bootdevs="$(awk -F ';' '/^boot/ { print $2 ";" $3 ";" $5 " "; }' $IGX_SYSCONF_FILE)"
    if [ -z "$bootdevs" ]; then
        igx_log "SUSPECT: Cannot find any devices containing MBR, step is skipped!"
        return 0
    fi
igx_log "Starting zeroeing first 2 gb of $DISK1"
dd if=/dev/zero of=$DISK1 bs=1M count=2048
igx_log "Starting zeroeing first 2 gb of $DISK2"
dd if=/dev/zero of=$DISK2 bs=1M count=2048
   
#    for devmbr in $bootdevs; do
#    
#        dev="$(echo $devmbr | awk -F ';' '{ print $1; }')"
#        mbr_file="$(echo $devmbr | awk -F ';' '{ print $2; }')"
#        dev_id="$(echo $devmbr | awk -F ';' '{ print $3; }')"
#        dev_id_cur="$(igx_disk_bypath $dev)"
#
#        if [ "$dev_id_cur" != "$dev_id" ]; then
#            igx_log "WARNING: $dev is not the orignal boot/root disk (original id: $dev_id current id: $dev_id_cur)!"
#            igx_menu_yesno "DANGER: $dev is not orignal, continue?" || return 1
#        fi
#
#
#
#        igx_log "Checking MBR from device $dev"
#        if [ ! -b "$dev" ]; then
#            igx_log "ERROR: Cannot find disk device $dev, ABORT!"
#            return 2
#        fi
#        
#        dd 2>/dev/null if="$dev" of="/tmp/mbr" bs=512 count=1
#        cur_cksum="$(cksum /tmp/mbr | awk '{ print $1 }')"
#        old_cksum="$(cksum $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/$mbr_file | awk '{ print $1 }')"
#        
#        if [ $cur_cksum -eq $old_cksum ]; then
#            igx_log "MBR from disk $dev needs no restore (cksum is $cur_cksum)"
#        else
#            igx_log "Restoring MBR from disk $dev"
#            dd 2>/dev/null if="$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/$mbr_file" of="$dev" count=1 bs=512
#            if [ $? -ne 0 ]; then
#                igx_log "ERROR: Cannot restore MBR for disk $dev, ABORT!"
#                return 2
#            else
#                igx_log "Re- reading partition table on $(echo $dev | sed 's/[[:digit:]]*$//g') (using fdisk)"
#                echo "w" | fdisk 2>&1 "$(echo $dev | sed 's/[[:digit:]]*$//g')"
#                igx_log "Waiting 5 seconds before we go ahead (udev needs that)..."
#                sleep 5
#            fi
#        fi
#
#    done

echo -e "n\nn\np\n1\n\n\nw" | fdisk $DISK1
echo -e "n\nn\np\n1\n\n\nw" | fdisk $DISK2
    
    return 0
}

#
# Set up md software raid by using $IGX_SYSCONF_FILE
#
restore_raid()
{
    igx_log "Re- creating software raid (md) devices"
    grep -e "^md;" "$IGX_SYSCONF_FILE" > /dev/null
    if [ $? -ne 0 ]; then
        igx_log "No software raid needs to be setup, skipped!"
        return 0
    fi
        
    md_devices="$(awk -F ';' '/^md/ { print $2; }' $IGX_SYSCONF_FILE | sort -u)"
    
    for md_dev in $md_devices; do
    
        if [ -b $md_dev ]; then
            igx_log "Raid device $md_dev allready exists, testing if device is up"
            mdadm -D $md_dev
            if [ $? -eq 0 ]; then
                igx_log "Raid device $md_dev is up"
                continue
            fi
            igx_log "Raid device $md_dev is not running, trying startup"
        fi
    
        md_disks="$(awk -F ';' '/^md/ { if($2 == "'$md_dev'") print $3; }' $IGX_SYSCONF_FILE | sort | tr '\n' ' ')"
        md_level="$(awk -F ';' '/^md/ { if($2 == "'$md_dev'") { gsub("raid", "", $4); print $4; } }' $IGX_SYSCONF_FILE | sort -u)"
        md_devs="$(echo $md_disks | wc -w)"
        
        igx_log "Bringing up raid device $md_dev (level=$md_level, disks=$md_disks)"
        igx_log "Testing if we can assemble raid without re-creation"
        
        
        igx_log "Assemble of raid device $md_dev failed, no old superblock found!"
        igx_log "We need to create a new raid$md_level on device $md_dev"
        
        mdadm --create /dev/md0 --assume-clean --run --level=1 --raid-devices=2 $PART1 $PART2 
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot re- create raid$md_level on device $md_dev, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 1
        fi

        igx_log "Raid$md_level on device $md_dev created!"
        IGX_GEN_MD_CONF=1
      
    done
    
    return 0
}

#
# Restoring VolumeGroups by using $IGX_SYSCONF_FILE
#
restore_lvm()
{
    igx_log "Restoring VolumeGroup(s)"
    
    vgs="$(awk -F ';' '/^pv/ { print $2; } ' $IGX_SYSCONF_FILE | sort -u)"
    pvs="$(awk -F ';' '/^pv/ { print $3 ";" $4 " "; }' $IGX_SYSCONF_FILE)"

    if [ -z "$vgs" ]; then
        igx_log "No VolumeGroups to restore, step is skipped!"
        return 0
    fi

    for pvuuid in $pvs; do
    
        pv="$(echo $pvuuid | awk -F ';' '{ print $1; }')"
        uuid="$(echo $pvuuid | awk -F ';' '{ print $2; }')"

        igx_log "Running pvcreate on dev $pv (restoring uuid: $uuid)"
        pvcreate -y -ff --norestorefile --uuid "$uuid" "$pv"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot prepare PV $pv for LVM usage, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 1
        else
            igx_log "PV $pv successfully prepared for LVM usage!"
        fi
        
    done
        
    for vg in $vgs; do
    
        igx_log "Restoring VolumeGroup $vg"
        vgcfgrestore "$vg"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot restore VolumeGroup $vg, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 2
        else
            igx_log "VolumeGroup $vg successfully restored!"
        fi
        
        igx_log "Activating VolumeGroup $vg"
        vgchange -a y "$vg"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot activate VolumeGroup $vg, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 3
        else
            igx_log "VolumeGroup $vg successfully activated!"
        fi
        
    done

    return 0
}

#
# Creating filesystems on devices by using $IGX_SYSCONF_FILE
#
restore_mkfs()
{
    igx_log "Creating filesystem on devices (mkfs)"
    
    bdisks="$(egrep '^fs;' $IGX_SYSCONF_FILE)"
    if [ -z "$bdisks" ]; then
        igx_log "SUSPECT: No devices found where a filesystem should created, step is skipped!"
        return 0
    fi
    igx_log "Making ext4 on /dev/md0 by hand"
sleep 3
mkfs.ext4 -U cbb9679c-ec28-4d02-93e9-c7d515df6d1e /dev/md0
sleep 3

    return 0
}

#
# Mounting blank new disks in temporary mountpoint by using $IGX_SYSCONF_FILE
#
restore_mount()
{
    igx_log "Mounting all Filesystem in /mnt"
    
    mounts="$(awk -F ';' '/^fs/ { if($3 != "swap") print $2 ";/mnt" $4 " "; }' $IGX_SYSCONF_FILE | sort -t ';' -k 2)"
    if [ -z "$mounts" ]; then
        igx_log "ERROR: No devices found to mount!"
        return 1
    fi
    
    for mount in $mounts; do
    
        bdev="$(echo $mount | awk -F ';' '{ print $1; }')"
        mp="$(echo $mount | awk -F ';' '{ print $2; }')"
        
        igx_log "Creating mountpoint $mp"
        mkdir -p "$mp"
        
        igx_log "Mounting $bdev on $mp"
        mount "$bdev" "$mp"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot mount $bdev on $mp, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 2
        else
            igx_log "Device $bdev successfully mounted on $mp! (go ahead in 4 sec.)"
            sleep 4
        fi

    done
    
    return 0
}

#
# Mount nfs filesystem to got recovery archive
#
init_backend()
{
    igx_log "Initializing restore backend"
    
    if [ ! -f "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf" ]; then
        igx_log "ERROR: Cannot find $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 1
    fi
    
    IGX_BACKEND_MOD="$(awk -F '#' '/MOD/ { print $2; }' $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf)"
    IGX_BACKEND_URL="$(awk -F '#' '/URL/ { print $2; }' $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf)"
    IGX_BACKEND_IMG="$(awk -F '#' '/IMG/ { print $2; }' $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf)"

    if [ -z "$IGX_BACKEND_MOD" ]; then
        igx_log "ERROR: Cannot find backend module name in $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 2
    fi
    
    if [ -z "$IGX_BACKEND_URL" ]; then
        igx_log "ERROR: Cannot find backend url in $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 3
    fi
    
    if [ -z "$IGX_BACKEND_IMG" ]; then
        igx_log "ERROR: Cannot find backend image url/name in $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 4
    fi
    
    igx_log "Restore backend is \"$IGX_BACKEND_MOD\" and will be used to get image content"
    igx_log "Trying to load backend $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD ..."
    
    if [ ! -f "$IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD" ]; then
        igx_log "ERROR: Cannot find/access restore module $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD, ABORT!"
        return 5
    fi
    
    . "$IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD"
    
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Load of $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD failure, ABORT!"
        return 6
    fi

    igx_log "Restore backend $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD successfully loaded!"
    igx_log "Running backend init() function"
    
    igx_restore_backend_status reset
    igx_restore_backend_init
    igx_restore_backend_status
    bret=$?
    
    if [ $bret -ne 0 ]; then
        igx_log "ERROR: Backend init() function exit with $bret, ABORT!"
        return 7
    fi
    
    return 0
}
#
# Function bind the backend by calling backend bind() function
#
bind_backend()
{
    igx_log "Executing backend $IGX_BACKEND_MOD bind() functions"
    
    igx_restore_backend_status reset
    igx_restore_backend_bind "$IGX_BACKEND_URL"
    igx_restore_backend_status
    bret=$?
    
    if [ $bret -ne 0 ]; then
        igx_log "ERROR: Backend bind() function exit with $bret, ABORT!"
        return 1
    fi
    
    return 0
}

#
# Function extract content from $IGX_BACKEND_IMG file
#
restore_filesystems()
{
    igx_log "Restoreing filesystems (extracting backup archive content)"
        
    igx_log "Changing directory to /mnt"
    
    cd /mnt
    if [ "$(pwd)" != "/mnt" ]; then
        igx_log "ERROR: Cannot change to directory /mnt, ABORT!"
        cd $OLDPWD
        return 2
    fi
        
    igx_log "Using backend $IGX_BACKEND_MOD run() function to get plain archive content"
    igx_restore_backend_status reset
    igx_restore_backend_run "$IGX_BACKEND_IMG" | /bin/cpio -imduv 2>&1 | dialog --aspect 1 --backtitle "$IGX_VERSION" --title "Ignite-LX Filesystem Restore (Archive Extract)" --progressbox 20 60

    igx_restore_backend_status
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Archive $IGX_BACKEND_IMG not successfully extracted, ABORT!"
        igx_log "       Possible that backend $IGX_BACKEND_MOD run() function failure!"
        cd $OLDPWD
        return 3
    else
        igx_log "Archvie $IGX_BACKEND_IMG successfully extarcted!"
    fi
    
    cd $OLDPWD
    
    igx_log "Backend $IGX_BACKEND_MOD end() function is called later if restore is fully complete!"
    
    return 0
}

#
# Fix grub installation on boot disks list in $IGX_SYSCONF_FILE
#
restore_grub()
{
    igx_log "Running grup-install on boot devices"

    if [ ! -x /mnt/sbin/grub-install -a ! -x /mnt/usr/sbin/grub-install -a ! -x /mnt/usr/sbin/grub-install.unsupported ]; then
        igx_log "ERROR: grub-install not found, maybe that system cannot boot!"
        igx_log "Update boot loader manual or leave it!"
        return 1
    fi
    
    bdisks="$(awk -F ';' '/^boot/ { print $2 " "; }' $IGX_SYSCONF_FILE)"
    if [ -z "$bdisks" ]; then
        igx_log "SUSPECT: No boot devices found, step is skipped!"
        return 0
    fi
    
    igx_log "Moving /dev temporary to /mnt/dev"
    mount -o move /dev /mnt/dev
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot move /dev mountpoint, ABORT!"
        return 3
    else
        igx_log "Mountpoint /dev successfully moved to /mnt/dev"
    fi
    
#    for disk in $bdisks; do
#        echo $disk | egrep '.*[[:digit:]]$' > /dev/null
#       if [ $? -eq 0 ]; then
#           igx_log "IGNORE: Device $disk is a partion and ignored!"
#            continue
#        fi

        igx_log "Calling grub-install (using chroot as wrapper) on device $disk"
chroot /mnt sh -c "echo '# grub.conf generated by anaconda'" > /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '#'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '# Note that you do not have to rerun grub after making changes to this file'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '# NOTICE:  You do not have a /boot partition.  This means that'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '#          all kernel and initrd paths are relative to /, eg.'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '#          root (hd0,0)'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '#          kernel /boot/vmlinuz-version ro root=/dev/md0'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '#          initrd /boot/initrd-[generic-]version.img'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '#boot=/dev/sda'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo 'default=0'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo 'timeout=5'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo 'splashimage=(hd0,0)/boot/grub/splash.xpm.gz'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo 'hiddenmenu'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo 'password --md5 $1$LdyF//$dXIrVpzzsIR0Bi2b/M9ns/'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo 'title PACCBET 1 (2.6.32-504.16.2z4.el6.x86_64)'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo         'root (hd0,0)'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo         'kernel /boot/vmlinuz-2.6.32-504.16.2z4.el6.x86_64 ro root=/dev/md0 LANG=ru_RU.UTF-8 rd_NO_LUKS crashkernel=auto SYSFONT=UniCyr_8x16  KEYBOARDTYPE=pc KEYTABLE=us rhgb quiet'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo         'initrd /boot/initramfs-2.6.32-504.16.2z4.el6.x86_64.img'" >> /mnt/boot/grub/grub.conf 
chroot /mnt sh -c "echo '# mdadm.conf written out by anaconda'" > /mnt/etc/mdadm.conf 
chroot /mnt sh -c "echo 'MAILADDR root'" >> /mnt/etc/mdadm.conf 
chroot /mnt sh -c "echo 'AUTO +imsm +1.x -all'" >> /mnt/etc/mdadm.conf 
chroot /mnt sh -c "echo 'DEVICE /dev/sda1 /dev/sdb1'" >> /mnt/etc/mdadm.conf 
chroot /mnt sh -c "echo 'ARRAY /dev/md0 level=raid1 devices=/dev/sda1,/dev/sdb1'" >> /mnt/etc/mdadm.conf 


echo "Deleting UDEV rules, and UIDs and MACs fror ifcfg"
sleep 3
sed -i '/HWADDR/d' /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i '/UUID/d' /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i '/HWADDR/d' /mnt/etc/sysconfig/network-scripts/ifcfg-eth1
sed -i '/UUID/d' /mnt/etc/sysconfig/network-scripts/ifcfg-eth1
rm -f /mnt/etc/udev/rules.d/70-persistent-net.rules

 
chroot /mnt sh -c "mount -t proc proc /proc/" 
chroot /mnt sh -c "mount -t sysfs sysfs /sys/" 
chroot /mnt sh -c "dracut -f"    
chroot /mnt sh -c "grub-install $DISK1" 
chroot /mnt sh -c "grub-install $DISK2" 


#       if [ $? -ne 0 ]; then
#            igx_log "ERROR: grub-install $disk failed, trying my luck with grub-install.unsupported command..."
#            chroot /mnt sh -c "grub-install.unsupported $disk"
#            if [ $? -ne 0 ]; then
#                igx_log "Moving /mnt/dev back to /dev"
#                mount -o move /mnt/dev /dev
#                igx_log "Please install / update boot loader manually!"
#                igx_log "ERROR: grub-install $disk failed, ABORT"
#                return 2
#            fi
#        fi

        igx_log "Restore of boot loader on $disk successful!"
 #   done
    
    igx_log "Moving /mnt/dev back to /dev"
    mount -o move /mnt/dev /dev
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot move /mnt/dev mountpoint, ABORT!"
        return 4
    else
        igx_log "Mountpoint /mnt/dev successfully moved to /dev"
    fi

    return 0
}

#
# Function execute seq. all the recovery steps.
#
run()
{
    step_ret=0
    repeat_step=0
    
    for step in $IGX_RECOVERY_STEPS; do
    
        while true; do
        
            repeat_step=0
            
            igx_log "----------------------------------------------------------------------------"
            igx_log "RUN STEP: $step"
            igx_log "----------------------------------------------------------------------------"
            igx_log " "
        
            sleep 1
    
            case "$step" in
                                    
                modules)
                    load_modules
                    panic "modules"
                    step_ret=$?
                ;;
            
                udev)
                    start_udev
                    panic "udev"
                    step_ret=$?
                ;;
            
                hostname)
                    restore_hostname
                    panic "hostname"
                    step_ret=$?
                ;;
            
                network)
                    restore_network
                    panic "network"
                    step_ret=$?
                ;; 
            
                init_backend)
                    init_backend
                    panic "init_backend"
                    step_ret=$?
                ;; 

                bind_backend)
                    bind_backend
                    panic "bind_backend"
                    step_ret=$?
                ;; 
            
                mbr)
                    restore_mbr
                    panic "mbr"
                    step_ret=$?
                ;; 
            
                raid)
                    restore_raid
                    panic "raid"
                    step_ret=$?
                ;;
            
                lvm)
                    restore_lvm
                    panic "lvm"
                    step_ret=$?
                ;;
            
                mkfs)
                    restore_mkfs
                    panic "mkfs"
                    step_ret=$?
                ;;
            
                mount_fs)
                    restore_mount
                    panic "mount_fs"
                    step_ret=$?
                ;; 
            
                extract)
                    restore_filesystems
                    panic "extract"
                    step_ret=$?
                ;;

                grub)
                    restore_grub
                    panic "grub"
                    step_ret=$?
                ;;
            
                *)
                    igx_log "ERROR: Recovery step \"$step\" not implemented yet, ABORT!"
                    false
                    panic "$step"
                    return 1
                ;;
        
            esac
        
            if [ $step_ret -ne 0 ]; then
                igx_menu_yesno "Continue Restore?"   || break 2
                igx_menu_yesno "Repeat step: $step?" && repeat_step=1
            else
                igx_log "----------------------------------------------------------------------------"
                igx_log "END STEP: $step (go ahead in 3 secs.)"
                igx_log "----------------------------------------------------------------------------"
                igx_log " "
                sleep 3
            fi
            
            if [ $repeat_step -eq 0 ]; then
                break
            fi

        done
        
    done
    
    if [ $step_ret -eq 0 ]; then
	reboot -f
        igx_menu_yesno "Ignite Finish! Reboot?" || igx_shell
    else
        igx_menu_yesno "Ignite Errors! Reboot?" || igx_shell
    fi
    
    return $ret
}

#
# Cleanup function for signal handling
#
cleanup()
{
    retval=$?
    exit $retval
}

#
# This function is execute if the script is called
#
main()
{
    usage $@    || return 1
    igx_chkenv  || return 2
    
    trap cleanup 2 15
    
    if [ ! -f /tmp/run_igx_resotre.tmp ]; then
        igx_log "ABORT: It seems you want to restore on a running Operating System, ABORT!"
        return 100
    fi 

    igx_log "Starting disaster recovery at $(igx_date)"
    
    run
    retval=$?
    
    igx_log "End of disaster recovery at $(igx_date)"
    
    if [ $retval -eq 0 ]; then

        igx_log "FINAL RESTORE STATUS: SUCCESS!"
    else
        igx_log "FINAL RESTORE STATUS: FAILED!"
    fi
    
    igx_restore_backend_log "$IGX_LOG_DIR/$IGX_LOG" || igx_shell
    igx_log "Calling backend $IGX_BACKEND end() function to finish backend usage"
    igx_restore_backend_end "$IGX_BACKEND_URL"      || igx_shell
        
    umount -a 2> /dev/null
    
    return $retval
}

#
# Execute the script by calling main() and reboot afterwards
#
main $@
reboot -f 
