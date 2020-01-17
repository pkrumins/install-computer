#!/bin/bash
#

set -ueo pipefail

in_array () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} <value> <array>"
        exit 1
    fi

    local -r value="$1" && shift
    local -r array=("$@")

    for element in "${array[@]}"; do
        [[ "$element" == "$value" ]] && return
    done

    false
}

join_strings () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} <separator> <string1> [string2 ...]"
        exit 1
    fi

    local -r separator="$1" && shift
    local -r strings=("$@")
    local -r IFS="$separator"

    echo "${strings[*]}"
}

link_configs () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} [--sudo] <src1> [src2 ...] <dst1> [dst2 ...]"
        exit 1
    fi

    local sudo_cmd=""
    if [[ $1 == "--sudo" ]]; then
        sudo_cmd="sudo" && shift
    fi

    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} [--sudo] <src1> [src2 ...] <dst1> [dst2 ...]"
        exit 1
    fi

    if (( $# % 2 == 1 )); then
        echo "Error: Couldn't link configuration files, source and destination files are uneven."
        exit 1
    fi

    local -r srcs_dsts=("$@")
    local -r total_links=$((${#srcs_dsts[@]} / 2));

    for ((i = 0; i < total_links; i++)); do
        src_index="$i"
        dst_index="$((total_links+i))"
        src=~/projects/dotfiles/"${srcs_dsts[$src_index]}"
        dst="${srcs_dsts[$dst_index]}"
        dst_dir="$(dirname "$dst")"

        if [[ ! -f "$src" && ! -d "$src" ]]; then
            echo "Error: Couldn't link $src to $dst, the source link $src doesn't exist."
            exit 1;
        fi

        if [[ ! -d "$dst_dir" ]]; then
            $sudo_cmd mkdir -p "$dst_dir" || {
                echo "Error: Couldn't link $src to $dst, creating $dst_dir failed with error code $?."
                exit 1
            }
        fi

        $sudo_cmd ln -fs "$src" "$dst" || {
            echo "Error: Couldn't link $src to $dst, ln failed with error code $?."
            exit 1
        }
    done
}

create_docker_networks () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} <name1> [name2 ...] <network1> [network2 ...]"
        exit 1
    fi

    if (( $# % 2 == 1 )); then
        echo "Error: Couldn't create docker networks, names and networks are uneven."
        exit 1
    fi

    local -r names_networks=("$@")
    local -r total_networks=$((${#names_networks[@]} / 2));

    for ((i = 0; i < total_networks; i++)); do
        name_index="$i"
        network_index="$((total_networks+i))"
        name="${names_networks[$name_index]}"
        network="${names_networks[$network_index]}"

        # TODO: check name format

        if [[ -z "$name" ]]; then
            echo "Error: Couldn't create a docker network, name was empty."
            exit 1;
        fi

        # TODO: check network format

        docker network create --subnet "$network" "$name" || {
            echo "Error: Couldn't create docker network $name ($network), docker failed with error code $?."
            exit 1
        }
    done
}

build_docker_images () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <dir1> [dir2 ...]"
        exit 1
    fi

    local -r docker_dirs=("$@")

    for docker_dir in "${docker_dirs[@]}"; do
        (
            local -r image_name="$(basename "$docker_dir")"
            cd "$docker_dir" || {
                echo "Error: Couldn't change directory to $docker_dir, cd failed with error code $?."
                exit 1
            };
            docker build -t "$image_name" . || {
                echo "Error: Building docker image $image_name failed with error code $?."
                exit 1
            };
        )
    done
}

install_hosts () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <hosts file>"
        exit 1
    fi

    local -r hosts_file="$1"

    if [[ ! -f "$hosts_file" ]]; then
        echo "Error: Hosts file $hosts_file doesn't exist."
        exit 1;
    fi

    if ! grep -q "# <install hosts>" /etc/hosts; then
        sudo bash -c "cat - >> /etc/hosts" <"$hosts_file"
    fi
}

install_rc_local () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <rc.local file>"
        exit 1
    fi

    local -r rc_local_file="$1"

    if [[ ! -f "$rc_local_file" ]]; then
        echo "Error: Rc.local file $rc_local_file doesn't exist."
        exit 1;
    fi

    sudo cp "$rc_local_file" /etc/rc.local || {
        echo "Error: Couldn't copy rc.local to /etc, cp exited with error code $?."
        exit 1
    }

    sudo chmod 0755 /etc/rc.local || {
        echo "Error: Chmod 0755 /etc/rc.local failed with error code $?."
        exit 1
    }
}

install_systemd_service () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <service file>"
        exit 1
    fi

    local -r service_file="$1"
    local -r service_name="$(basename "$service_file")"

    if [[ ! -f "$service_file" ]]; then
        echo "Error: Systemd service file $service_file doesn't exist."
        exit 1;
    fi

    sudo cp "$service_file" "/etc/systemd/system/$service_file" || {
        echo "Error: Copying $service_file to /etc/systemd/system failed with error code $?"
        exit 1;
    }

    sudo systemctl enable "$service_name" || {
        echo "Error: Couldn't enable systemd service $service_name, error code $?"
        exit 1;
    }

    sudo systemctl start "$service_name" || {
        echo "Error: Couldn't start systemd service $service_name, error code $?"
        exit 1;
    }
}

add_user_to_groups () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} <user> <group1> [group2 ...]"
        exit 1
    fi

    local -r user="$1" && shift
    local -r groups=("$@")
    local -r csv_groups="$(join_strings "," "${groups[@]}")"

    sudo usermod -a -G "$csv_groups" "$user" || {
        echo "Error: Couldn't add the user $user to groups $csv_groups, usermod exited with error code $?."
        exit 1
    }
}

check_required_file () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <file>"
        exit 1
    fi

    local -r file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Error: File $file doesn't exist, check the install scripts."
        exit 1;
    fi
}

check_required_dir () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <directory>"
        exit 1
    fi

    local -r dir="$1"
    local -r git_dir="$1/.git"
    local -r base_dir="$(basename "$dir")"

    if [[ ! -d "$dir" ]]; then
        echo "Error: Directory $base_dir doesn't exist, pull it first."
        exit 1
    fi

    if [[ ! -d "$git_dir" ]]; then
        echo "Error: Directory $base_dir is not a git repository."
        exit 1
    fi
}

install_pip_packages () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <package1> [package2 ...]"
        exit 1
    fi

    local -r packages=("$@")

    pip3 install "${packages[@]}" || {
        echo "Error: Installing pip packages failed with error code $?."
        exit 1
    }
}

uninstall_apt_packages () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <package1> [package2 ...]"
        exit 1
    fi

    local -r packages=("$@")

    sudo apt-get --purge autoremove -y "${packages[@]}" || true
}

install_apt_packages () {
    if (( $# < 1 )); then
        echo "Usage: ${FUNCNAME[0]} <package1> [package2 ...]"
        exit 1
    fi

    local -r packages=("$@")

    sudo apt-get install -y "${packages[@]}" || {
        echo "Error: Installing apt packages failed with error code $?."
        exit 1
    }
}

main () {
    if (( $# < 1 )); then
        echo "Usage: $0 <desktop|laptop>"
        exit 1
    fi

    local -r COMPUTER_TYPE="$1"

    if [[ $COMPUTER_TYPE != "desktop" && $COMPUTER_TYPE != "laptop" ]]; then
        echo "Error: Incorrect computer type, should be either a desktop or a laptop."
        exit 1
    fi

    # Create /.computer-$COMPUTER_TYPE file
    #
    sudo touch "/.computer-$COMPUTER_TYPE" || {
        echo "Error: Unable to create /.computer-$COMPUTER_TYPE file, touch failed with error code $?."
        exit 1
    }

    local -r SCRIPT_DIR="$(dirname "$(realpath $0)")"

    check_required_dir ~/projects/dotfiles
    check_required_dir ~/projects/dockerfiles
    check_required_file "$SCRIPT_DIR/rc.local"
    check_required_file "$SCRIPT_DIR/rc-local.service"
    check_required_file "$SCRIPT_DIR/hosts"

    sudo apt-get update || {
        echo "Error: apt-get update failed with error code $?."
        exit 1
    }

    # Uninstall unneed packages
    #
    local -r unneeded_packages=(
        nano
    )

    uninstall_apt_packages "${unneeded_packages[@]}"

    # Install apt and pip packages
    #
    local -r x_packages=(
        xinit
        rxvt-unicode
        i3
        xss-lock
        x11-xserver-utils
        xsel
        xinput
        arandr
        ttf-dejavu
        wmctrl
        xdotool
    );
    local -r dev_packages=(
        gcc
        g++
        make
        autoconf
        pkg-config
        python-pip
        python3-pip
        exuberant-ctags
        libpcre2-dev
        libncurses5-dev
        libncursesw5-dev
    );
    local -r docker_packages=(
        docker.io
    );
    local -r sound_packages=(
        alsa
        pulseaudio
    );
    local -r net_packages=(
        net-tools
        netcat
        whois
        ipcalc
    );
    local -r extra_packages=(
        zip
        ncdu
        most
        tree
        pv
        bvi
        fdupes
        rlwrap
        wamerican
        nfs-common
        apt-file
        lm-sensors
        msort
        libimage-exiftool-perl
        moreutils
    );
    local -r laptop_packages=(
        powertop
        wireless-tools
    );
    local -r pip_packages=(
        ranger-fm
    );

    install_apt_packages "${x_packages[@]}"
    install_apt_packages "${dev_packages[@]}"
    install_apt_packages "${docker_packages[@]}"
    install_apt_packages "${sound_packages[@]}"
    install_apt_packages "${net_packages[@]}"
    install_apt_packages "${extra_packages[@]}"

    if [[ $COMPUTER_TYPE == "laptop" ]]; then
        install_apt_packages "${laptop_packages[@]}"
    fi

    install_pip_packages "${pip_packages[@]}"

    if in_array "apt-file" "${extra_packages[@]}"; then
        sudo apt-file update || {
            echo "Error: Running apt-file update failed with error code $?."
            exit 1;
        }
    fi

    # Add the current user to extra groups
    #
    local -r extra_groups=(
        audio
        video
        docker
    );

    add_user_to_groups "$USER" "${extra_groups[@]}"

    # Build docker images from ~/projects/dockerfiles subdirectories
    #
    local -r docker_files=($(
        find ~/projects/dockerfiles \
            -maxdepth 1 \
            -mindepth 1 \
            -type d \
            -not -path */.git \
            -not -path */*-todo | sort
    ))

    build_docker_images "${docker_files[@]}"

    # Create docker networks
    local -Ar docker_networks=(
        ["lamp"]="10.10.10.0/24"
    );

    create_docker_networks "${!docker_networks[@]}" "${docker_networks[@]}"

    # Link configurations from ~/projects/dotfiles
    #
    local -A configs=(
        ["bin"]=~/bin
        [".bashrc"]=~/.bashrc
        [".inputrc"]=~/.inputrc
        [".screenrc"]=~/.screenrc
        [".tmux.conf"]=~/.tmux.conf
        [".vim"]=~/.vim
        [".vimrc"]=~/.vimrc
        [".mostrc"]=~/.mostrc
        [".config/i3"]=~/.config/i3
        [".urxvt"]=~/.urxvt
        [".fonts"]=~/.fonts
        [".fonts.conf"]=~/.fonts.conf
        [".xsessionrc"]=~/.xsessionrc
        [".Xresources"]=~/.Xresources
    );
    local -A sudo_configs=(
        ["etc/X11/xorg.conf"]=/etc/X11/xorg.conf
    );

    if [[ $COMPUTER_TYPE == "desktop" ]]; then
        configs[".asoundrc"]=~/.asoundrc
    fi

    local -r configs sudo_configs

    link_configs "${!configs[@]}" "${configs[@]}"
    link_configs --sudo "${!sudo_configs[@]}" "${sudo_configs[@]}"

    # .Xresources customization on a laptop
    #
    if [[ $COMPUTER_TYPE == "laptop" ]]; then
        # Enable high DPI on a laptop
        sed -i 's/^!Xft.dpi:/Xft.dpi:/' ~/.Xresources
    fi

    # Install /etc/rc.local script
    #
    install_rc_local "$SCRIPT_DIR/rc.local"

    # Create rc-local systemd service
    #
    install_systemd_service "$SCRIPT_DIR/rc-local.service"

    # Install /etc/hosts
    #
    install_hosts "$SCRIPT_DIR/hosts"

    # Set timezone to UTC
    #
    sudo timedatectl set-timezone UTC || {
        echo "Error: Setting timezone to UTC failed with error code $?."
        exit 1;
    }

    echo "Your $COMPUTER_TYPE computer has been installed."
    echo
    echo "Manual tasks:"
    echo "1) Copy ssh keys to ~/.ssh"
    echo "2) Copy keepass database to ~/keepassxc"
    echo "3) Run prepare-chrome-data-dir command and setup chrome template"
}

main "$@"

