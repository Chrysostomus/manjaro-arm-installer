#!/bin/bash
# Installer for manjaro-arm


#################
### Variables ###

# Header
VERSION="Manjaro-arm Installer v0.1"

# Host system information
ARCHI=$(uname -m)  # Display whether 32 or 64 bit system
SYSTEM="Unknown"   # Display whether system is BIOS or UEFI. Default is "unknown"
H_INIT=""          # Host init-sys
NW_CMD=""          # command to launch the available network client

# Locale and Language
CURR_LOCALE="en_US.UTF-8"   # Default Locale
FONT=""                     # Set new font if necessary
KEYMAP="us"                 # Virtual console keymap. Default is "us"
XKBMAP="us"                 # X11 keyboard layout. Default is "us"
ZONE=""                     # For time
SUBZONE=""                  # For time
LOCALE="en_US.UTF-8"        # System locale. Default is "en_US.UTF-8"
PROFILES=""                 # iso-profiles path

# Menu highlighting (automated step progression)
HIGHLIGHT=0                 # Highlight items for Main Menu
HIGHLIGHT_SUB=0             # Highlight items for submenus
SUB_MENU=""                 # Submenu to be highlighted
PARENT=""                   # the parent menu
INIFILE="/tmp/manjaro-architect.ini"
# Mounting
MOUNT=""                        # Installation: All other mounts branching
MOUNTPOINT="/mnt"               # Installation: Root mount from Root
FS_OPTS=""                      # File system special mount options available
CHK_NUM=16                      # Used for FS mount options checklist length
INCLUDE_PART='part\|lvm\|crypt' # Partition types to include for display and selection.
ROOT_PART=""                    # ROOT partition

#############
### Menus ###
main_menu() {
    declare -i loopmenu=1
    while ((loopmenu)); do
        if [[ $HIGHLIGHT != 6 ]]; then
           HIGHLIGHT=$(( HIGHLIGHT + 1 ))
        fi

        DIALOG " $_MMTitle " --default-item ${HIGHLIGHT} \
          --menu "\n$_MMNewBody\n " 0 0 6 \
          "1" "$_PrepMenuTitle|>" \
          "2" "$_InstBse|>" \
          "3" "$_ConfBseMenuTitle|>" \
          "4" "$_InstMulCust" \
          "5" "$_ChrootTitle" \
          "6" "$_Done" 2>${ANSWER}
        HIGHLIGHT=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") prep_menu
                ;;
            "2") check_mount && install_base
                ;;
            "3") check_base && config_base_menu
                ;;
            "4") install_cust_pkgs
                ;;
            "5") check_base && chroot_interactive
                ;;
             *) loopmenu=0
                exit_done
                ;;
        esac
    done
}

# Preparation
prep_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        submenu 9
        DIALOG " $_PrepMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_PrepMenuBody\n " 0 0 9 \
          "1" "$_VCKeymapTitle" \
          "2" "$_DevShowOpt" \
          "3" "$_PrepPartDisk" \
          "4" "$_PrepMntPart" \
          "5" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") select_keymap
                 set_keymap
                 ;;
            "2") show_devices
                 ;;
            "3") umount_partitions
                 select_device && create_partitions
                 ;;
            "4") mount_partitions
                 ;;
            *) loopmenu=0
                return 0
                 ;;
        esac
    done
}

# Base Configuration
config_base_menu() {
    local PARENT="$FUNCNAME"
    declare -i loopmenu=1
    while ((loopmenu)); do
        ssubmenu 8
        DIALOG " $_ConfBseMenuTitle " --default-item ${HIGHLIGHT_SSUB} --menu "\n$_ConfBseBody\n " 0 0 8 \
          "1" "$_ConfBseFstab" \
          "2" "$_ConfBseHost" \
          "3" "$_ConfBseSysLoc" \
          "4" "$_PrepKBLayout" \
          "5" "$_ConfBseTimeHC" \
          "6" "$_ConfUsrRoot" \
          "7" "$_ConfUsrNew" \
          "8" "$_Back" 2>${ANSWER}
        HIGHLIGHT_SSUB=$(cat ${ANSWER})

        case $(cat ${ANSWER}) in
            "1") generate_fstab
                ;;
            "2") set_hostname
                ;;
            "3") set_locale
                ;;
            "4") set_xkbmap
                ;;
            "5") set_timezone && set_hw_clock
                ;;
            "6") set_root_password
                ;;
            "7") create_new_user
                ;;
            *) loopmenu=0
                return 0
                ;;
        esac
    done
}

#################
### Functions ###

# Themed dilog window
DIALOG() {
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --column-separator "|" --exit-label "$_Back" --title "$@"
}

# Download a file with wget and show progressbar
download_progress() {
	URL="$1"
	wget --continue "$URL" 2>&1 | \
	 stdbuf -o0 awk '/[.] +[0-9][0-9]?[0-9]?%/ { print substr($0,63,3) }' | \
	 DIALOG --gauge "Download Test" 10 100
}

# Function to collect information into a ini file
ini() {
    local section="$1" value="$2"
    [[ ! -f "$INIFILE" ]] && echo "">"$INIFILE"
    if [[ ! "$section" =~ \. ]]; then
        section="manjaro-arm.${section}"
    fi
    ini_val "$INIFILE" "$section" "$value" 2>/dev/null
}

function finishini {
    [[ -f "$INIFILE" ]] && mv "$INIFILE" "/var/log/m-a.ini" &>/dev/null
    ((debug)) && cat "/var/log/m-a.ini"
}
trap finishini EXIT

# progress through menu entries until number $1 is reached
submenu() {
    if [[ $SUB_MENU != "$PARENT" ]]; then
        SUB_MENU="$PARENT"
        HIGHLIGHT_SUB=1
    elif [[ $HIGHLIGHT_SUB != "$1" ]]; then
        HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
    fi
}

ssubmenu() {
    if [[ $SSUB_MENU != "$PARENT" ]]; then
        SSUB_MENU="$PARENT"
        HIGHLIGHT_SSUB=1
    elif [[ $HIGHLIGHT_SSUB != "$1" ]]; then
        HIGHLIGHT_SSUB=$(( HIGHLIGHT_SSUB + 1 ))
    fi
}

check_root() {
    if [[ `whoami` != "root" ]]; then
        DIALOG " $_ErrTitle " --infobox "\n$_RtFailBody\n " 0 0
        sleep 3
        clear
        exit 1
    fi
}
# Simple code to show devices / partitions.
show_devices() {
    lsblk -o NAME,MODEL,TYPE,FSTYPE,SIZE,MOUNTPOINT | grep "disk\|part\|lvm\|crypt\|NAME\|MODEL\|TYPE\|FSTYPE\|SIZE\|MOUNTPOINT" > /tmp/.devlist
    DIALOG " $_DevShowOpt " --textbox /tmp/.devlist 0 0
}

# Adapted from AIS. An excellent bit of code!
arch_chroot() {
    manjaro-chroot $MOUNTPOINT "${1}"
}

# Ensure that a partition is mounted
check_mount() {
    if [[ $(lsblk -o MOUNTPOINT | grep ${MOUNTPOINT}) == "" ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_ErrNoMount\n " 0 0
        ANSWER=0
        HIGHLIGHT=0
        return 1
    fi
}

# Ensure that Manjaro has been installed
check_base() {
    check_mount
    if [[ $? -eq 0 ]]; then
        if [[ ! -e /mnt/.base_installed ]]; then
            DIALOG " $_ErrTitle " --msgbox "\n$_ErrNoBase\n " 0 0
            ANSWER=1
            HIGHLIGHT=1
            HIGHLIGHT_SUB=2
            return 1
        fi
    else
        return 1
    fi
}

# Function will not allow incorrect UUID type for installed system.
generate_fstab() {
    DIALOG " $_ConfBseFstab " --menu "\n$_FstabBody\n " 0 0 4 \
      "fstabgen -p" "$_FstabDevName" \
      "fstabgen -L -p" "$_FstabDevLabel" \
      "fstabgen -U -p" "$_FstabDevUUID" \
      "fstabgen -t PARTUUID -p" "$_FstabDevPtUUID" 2>${ANSWER}

    if [[ $(cat ${ANSWER}) != "" ]]; then
        if [[ $SYSTEM == "BIOS" ]] && [[ $(cat ${ANSWER}) == "fstabgen -t PARTUUID -p" ]]; then
            DIALOG " $_ErrTitle " --msgbox "\n$_FstabErr\n " 0 0
        else
            $(cat ${ANSWER}) ${MOUNTPOINT} > ${MOUNTPOINT}/etc/fstab 2>$ERR
            check_for_error "$FUNCNAME" $?
            [[ -f ${MOUNTPOINT}/swapfile ]] && sed -i "s/\\${MOUNTPOINT}//" ${MOUNTPOINT}/etc/fstab
        fi
    fi
}

# locale array generation code adapted from the Manjaro 0.8 installer
set_locale() {
    LOCALES=""
    for i in $(cat /etc/locale.gen | grep -v "#  " | sed 's/#//g' | awk '/UTF-8/ {print $1}'); do
        LOCALES="${LOCALES} ${i} -"
    done

    DIALOG " $_ConfBseSysLoc " --menu "\n$_localeBody\n " 0 0 12 ${LOCALES} 2>${ANSWER} || return 0

    LOCALE=$(cat ${ANSWER})

    echo "LANG=\"${LOCALE}\"" > ${MOUNTPOINT}/etc/locale.conf
    sed -i "s/#${LOCALE}/${LOCALE}/" ${MOUNTPOINT}/etc/locale.gen 2>$ERR
    arch_chroot "locale-gen" >/dev/null 2>$ERR
    check_for_error "$FUNCNAME" "$?"
    ini linux.locale "$LOCALE"

}

# Set Zone and Sub-Zone
set_timezone() {
    ZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud); do
        ZONE="$ZONE ${i} -"
    done

    DIALOG " $_ConfBseTimeHC " --menu "\n$_TimeZBody\n " 0 0 10 ${ZONE} 2>${ANSWER} || return 1
    ZONE=$(cat ${ANSWER})

    SUBZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "${ZONE}/" | sed "s/${ZONE}\///g" | sort -ud); do
        SUBZONE="$SUBZONE ${i} -"
    done

    DIALOG " $_ConfBseTimeHC " --menu "\n$_TimeSubZBody\n " 0 0 11 ${SUBZONE} 2>${ANSWER} || return 1
    SUBZONE=$(cat ${ANSWER})

    DIALOG " $_ConfBseTimeHC " --yesno "\n$_TimeZQ ${ZONE}/${SUBZONE}?\n " 0 0
    if (( $? == 0 )); then
        arch_chroot "ln -sf /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime" 2>$ERR
        check_for_error "$FUNCNAME ${ZONE}/${SUBZONE}" $?
        ini linux.zone "${ZONE}/${SUBZONE}"
    else
        return 1
    fi
}

set_hw_clock() {
    DIALOG " $_ConfBseTimeHC " --menu "\n$_HwCBody\n " 0 0 2 \
    "utc" "-" \
    "localtime" "-" 2>${ANSWER}

    if [[ $(cat ${ANSWER}) != "" ]]; then
        arch_chroot "hwclock --systohc --$(cat ${ANSWER})"  2>$ERR
        check_for_error "$FUNCNAME" "$?"
        ini linux.time "$ANSWER"
    fi
}

set_hostname() {
    DIALOG " $_ConfBseHost " --inputbox "\n$_HostNameBody\n " 0 0 "manjaro" 2>${ANSWER} || return 0

    echo "$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hostname 2>$ERR
    echo -e "#<ip-address>\t<hostname.domain.org>\t<hostname>\n127.0.0.1\tlocalhost.localdomain\tlocalhost\t$(cat \
      ${ANSWER})\n::1\tlocalhost.localdomain\tlocalhost\t$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hosts 2>$ERR
    check_for_error "$FUNCNAME"
    ini linux.hostname "$ANSWER"
}

# Adapted and simplified from the Manjaro 0.8 and Antergos 2.0 installers
set_root_password() {
    DIALOG " $_ConfUsrRoot " --clear --insecure --passwordbox "\n$_PassRtBody\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})

    DIALOG " $_ConfUsrRoot " --clear --insecure --passwordbox "\n$_PassReEntBody\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD2=$(cat ${ANSWER})

    if [[ $PASSWD == $PASSWD2 ]]; then
        echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
        arch_chroot "passwd root" < /tmp/.passwd >/dev/null 2>$ERR
        check_for_error "$FUNCNAME" $?
        rm /tmp/.passwd
    else
        DIALOG " $_ErrTitle " --msgbox "\n$_PassErrBody\n " 0 0
        set_root_password
    fi
}

# Originally adapted from the Antergos 2.0 installer
create_new_user() {
    DIALOG " $_NUsrTitle " --inputbox "\n$_NUsrBody\n " 0 0 "" 2>${ANSWER} || return 0
    USER=$(cat ${ANSWER})

    # Loop while user name is blank, has spaces, or has capital letters in it.
    while [[ ${#USER} -eq 0 ]] || [[ $USER =~ \ |\' ]] || [[ $USER =~ [^a-z0-9\ ] ]]; do
        DIALOG " $_NUsrTitle " --inputbox "$_NUsrErrBody" 0 0 "" 2>${ANSWER} || return 0
        USER=$(cat ${ANSWER})
    done

    shell=""
    DIALOG " $_NUsrTitle " --radiolist "\n$_DefShell\n$_UseSpaceBar\n " 0 0 3 \
      "zsh" "-" on \
      "bash" "-" off \
      "fish" "-" off 2>/tmp/.shell
    shell_choice=$(cat /tmp/.shell)

    case ${shell_choice} in
        "zsh") [[ ! -e /mnt/etc/skel/.zshrc ]] && basestrap ${MOUNTPOINT} manjaro-zsh-config
            shell=/usr/bin/zsh
            ;;
        "fish") [[ ! -e /mnt/usr/bin/fish ]] && basestrap ${MOUNTPOINT} fish
            shell=/usr/bin/fish
            ;;
        "bash") shell=/bin/bash
            ;;
    esac
    check_for_error "default shell: [${shell}]"

    # Enter password. This step will only be reached where the loop has been skipped or broken.
    DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n$_PassNUsrBody $USER\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})

    DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n$_PassReEntBody\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD2=$(cat ${ANSWER})

    # loop while passwords entered do not match.
    while [[ $PASSWD != $PASSWD2 ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_PassErrBody\n " 0 0

        DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n$_PassNUsrBody $USER\n " 0 0 \
          2> ${ANSWER} || return 0
        PASSWD=$(cat ${ANSWER})

        DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n_PassReEntBody\n " 0 0 \
          2> ${ANSWER} || return 0
        PASSWD2=$(cat ${ANSWER})
    done

    # create new user. This step will only be reached where the password loop has been skipped or broken.
    DIALOG " $_ConfUsrNew " --infobox "\n$_NUsrSetBody\n " 0 0
    sleep 2

    local list=$(ini linux.users)
    [[ -n "$list" ]] && list="${list};"
    ini linux.users "${list}${USER}"
    list=$(ini linux.shells)
    [[ -n "$list" ]] && list="${list};"
    ini linux.shells "${list}${shell}"

    # Create the user, set password, then remove temporary password file
    arch_chroot "groupadd ${USER}"
    arch_chroot "useradd ${USER} -m -g ${USER} -G wheel,storage,power,network,video,audio,lp -s $shell" 2>$ERR
    check_for_error "add user to groups" $?
    echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
    arch_chroot "passwd ${USER}" < /tmp/.passwd >/dev/null 2>$ERR
    check_for_error "create user pwd" $?
    rm /tmp/.passwd

    # Set up basic configuration files and permissions for user
    #arch_chroot "cp /etc/skel/.bashrc /home/${USER}"
    arch_chroot "chown -R ${USER}:${USER} /home/${USER}"
    [[ -e ${MOUNTPOINT}/etc/sudoers ]] && sed -i '/%wheel ALL=(ALL) ALL/s/^#//' ${MOUNTPOINT}/etc/sudoers
}

mount_partitions() {

}

chroot_interactive() {

DIALOG " $_EnterChroot " --infobox "$_ChrootReturn" 0 0 
echo ""
echo ""
arch_chroot bash
}

# Set keymap for X11
set_xkbmap() {
    XKBMAP_LIST=""
    keymaps_xkb=("af al am at az ba bd be bg br bt bw by ca cd ch cm cn cz de dk ee es et eu fi fo fr\
      gb ge gh gn gr hr hu ie il in iq ir is it jp ke kg kh kr kz la lk lt lv ma md me mk ml mm mn mt mv\
      ng nl no np pc ph pk pl pt ro rs ru se si sk sn sy tg th tj tm tr tw tz ua us uz vn za")

    for i in ${keymaps_xkb}; do
        XKBMAP_LIST="${XKBMAP_LIST} ${i} -"
    done

    DIALOG " $_PrepKBLayout " --menu "\n$_XkbmapBody\n " 0 0 16 ${XKBMAP_LIST} 2>${ANSWER} || return 0
    XKBMAP=$(cat ${ANSWER} |sed 's/_.*//')
    echo -e "Section "\"InputClass"\"\nIdentifier "\"system-keyboard"\"\nMatchIsKeyboard "\"on"\"\nOption "\"XkbLayout"\" "\"${XKBMAP}"\"\nEndSection" \
      > ${MOUNTPOINT}/etc/X11/xorg.conf.d/00-keyboard.conf 2>$ERR
    check_for_error "$FUNCNAME ${XKBMAP}" "$?"
}


###################
### Main section###

main_menu