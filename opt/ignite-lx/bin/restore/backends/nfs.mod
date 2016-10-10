# nfs.mod
# 
#
# Created by Daniel Faltin on 29.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

#
# Module implements Ignite-LX NFS Restore
#
# This functions are include / loaded from make_restore.sh
# Each backend must define the three major restore functions
#

#
# This function return 0 (success) or 1 (fail) in case if any error has occurred.
# Function can call any time to check the correct work of this backend.
# Arguments: <string> if any argument is defined, status will be resetted
# Return: zero on success otherwise a non zero value
#
igx_restore_backend_status()
{
    _igx_nfs_retval=$?

    if [ "x$@" != "x" -o "x$IGX_RESTORE_BACKEND_STATUS" = "x" ]; then
        IGX_RESTORE_BACKEND_STATUS=0
        return 0
    fi

    if [ $_igx_nfs_retval -ne 0 ]; then
        IGX_RESTORE_BACKEND_STATUS=$_igx_nfs_retval
    fi

    return $IGX_RESTORE_BACKEND_STATUS
}

#
# Run some pre- required activities like service start etc. 
# Arguments: none
# Return: zero on success otherwise a non zero value
#
igx_restore_backend_init() 
{
    igx_log "Starting portmap daemon"
    
#    /sbin/portmap
#    if [ $? -ne 0 ]; then
#        false
#        igx_restore_backend_status
#        igx_log "ERROR: Cannot startup portmap daemon, ABORT!"
#        igx_log "Please try to start /sbin/portmap manually and mount nfs share!"
#        return 1
#    else
#        igx_log "Portmap daemon successfully started!"
#    fi

    return 0
}

#
# Function bind the image location (if required) like mount etc.
# Arguments: <string> typical a url and image name to use internal in this function
# Return: zero on success otherwise a non zero value
#
igx_restore_backend_bind() 
{
    URL="$@"

    igx_log "Mounting NFS Image share (from: $URL to: $IGX_NFS_MOUNTPOINT)"
    
    if [ "x$URL" = "x" ]; then
        flase
        igx_restore_backend_status
        igx_log "ERROR: Cannot find URL as argument, ABORT!"
        return 1
    fi
    
#    if [ "x$IGX_NFS_MOUNTPOINT" = "x" ]; then
        IGX_NFS_MOUNTPOINT="/opt/ignite-lx/mnt/arch_mnt"
#    fi
        
    if [ ! -d "$IGX_NFS_MOUNTPOINT" ]; then
        igx_log "Creating archive mountpoint $IGX_NFS_MOUNTPOINT"
        mkdir -p "$IGX_NFS_MOUNTPOINT"
        if [ ! -d "$IGX_NFS_MOUNTPOINT" ]; then
            flase
            igx_restore_backend_status
            igx_log "ERROR: Cannot create directory $IGX_NFS_MOUNTPOINT, ABORT!"
            igx_log "Create $IGX_NFS_MOUNTPOINT manually and mount nfs share!"
            return 2
        else
            igx_log "Archive mountpoint $IGX_NFS_MOUNTPOINT successfully created!"
        fi
    fi
    
    igx_log "Trying mount of $URL on $IGX_NFS_MOUNTPOINT ..."

igx_log "Mkdir for usb flash disk on /mnt/usbflash"
mkdir /mnt/usbflash
igx_log "Mounting /dev/sda1 to /mnt/usbflash"
#mount -t vfat /dev/sda1 /mnt/usbflash
mount /dev/sr0 /mnt/usbflash
igx_log "Try to mount /mnt/usbflash/filesystem to $IGX_NFS_MOUNTPOINT"
mount /mnt/usbflash/filesystem $IGX_NFS_MOUNTPOINT  


#    mount.nfs "$URL" "$IGX_NFS_MOUNTPOINT" -w -v -o nolock,soft
#    if [ $? -ne 0 ]; then
#        false
#        igx_restore_backend_status
#        igx_log "ERROR: Mount of $URL on $IGX_NFS_MOUNTPOINT failure, ABORT!"
#        igx_log "Please mount nfs share on $IGX_NFS_MOUNTPOINT manually!"
#        return 2
#    fi
    
#    igx_log "Mount of $URL on $IGX_NFS_MOUNTPOINT successfully!"
    
    return 0
}

#
# Function print to stdout the plain cpio archive content
# Arguments: <string> image url (path, link, etc.) to get
# Return: zero on success otherwise a non zero value
#
igx_restore_backend_run()
{
    IMG="$@"

#    if [ "x$IGX_NFS_MOUNTPOINT" = "x" ]; then
        IGX_NFS_MOUNTPOINT="/opt/ignite-lx/mnt/arch_mnt"
#    fi

#    if [ ! -r "$IMG" ]; then
#        if [ ! -r "$IGX_NFS_MOUNTPOINT/$IMG" ]; then
#            false
#            igx_restore_backend_status
#            igx_log "ERROR: Cannot find/read image file $IMG for restore, ABORT!"
#            return 1
#        else
            IMG_FILE="$IGX_NFS_MOUNTPOINT/$IMG"
#        fi
#    else
#        IMG_FILE="$IMG"
#    fi
    
    gzip -cd "$IMG_FILE"
    
    if [ $? -ne 0 ]; then
        false
        igx_restore_backend_status
        igx_log "ERROR: Unzip of file $IMG_FILE failed, ABORT!"
        return 2
    fi

    igx_log "Unzip of $IMG_FILE successful!"
    
    return 0
}

#
# Function move or copy the logfile on the same location where image is located.
# Arguments: <string> typical a logfile to move
# Return: zero on success otherwise a non zero value
#
igx_restore_backend_log()
{
    move_log="$@"
    
    igx_log "Copying logfile $move_log to NFS share $IGX_NFS_MOUNTPOINT"
    cp "$move_log" "$IGX_NFS_MOUNTPOINT"
    if [ $? -ne 0 ]; then
        false
        igx_restore_backend_status
        igx_log "ERROR: Cannot copy logfile, please do this manual, ABORT!"
        return 1
    fi
    
    return 0
}

#
# Function finish / cleanup the usage of this backend.
# Arguments: <string> typical a url to use internal in this function
# Return: zero on success otherwise a non zero value
#
igx_restore_backend_end()
{
    URL="$@"
    
    if [ "x$IGX_NFS_MOUNTPOINT" = "x" ]; then
        IGX_NFS_MOUNTPOINT="/opt/ignite-lx/mnt/arch_mnt"
    fi

    igx_log "Unmounting $IGX_NFS_MOUNTPOINT (from: $URL)"
 
    umount "$IGX_NFS_MOUNTPOINT"
    
    if [ $? -ne 0 ]; then
        false
        igx_restore_backend_status
        igx_log "ERROR: Unmount of $IGX_NFS_MOUNTPOINT failed, ABORT!"
        return 1
    fi
    
    igx_log "Unmount of $IGX_NFS_MOUNTPOINT successful!"
    
    return 0
}
