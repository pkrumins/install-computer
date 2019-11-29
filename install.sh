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

    echo "$*"
}

link_configs () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} [--sudo] <src1> <dst1> [src2 dst2 ...]"
        exit 1
    fi

    local sudo_cmd=""
    if [[ $1 == "--sudo" ]]; then
        sudo_cmd="sudo" && shift
    fi

    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} [--sudo] <src1> <dst1> [src2 dst2 ...]"
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
                echo "Error: Couldn't link $src to $dst, creating $dst_dir failed with error code $?"
                exit 1
            }
        fi

        $sudo_cmd ln -fs "$src" "$dst" || {
            echo "Error: Couldn't link $src to $dst, ln failed with error code $?."
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
            docker build -t "$image_name" - < Dockerfile || {
                echo "Error: Building docker image $image_name failed with error code $?."
                exit 1
            };
        )
    done
}

add_user_to_groups () {
    if (( $# < 2 )); then
        echo "Usage: ${FUNCNAME[0]} <user> <group1> [group2 ...]"
        exit 1
    fi

    local -r user="$1" && shift
    local -r groups=("$@")
    local -r csv_groups="$(join_strings "${groups[@]}")"

    sudo usermod -a -G "$csv_groups" "$user" || {
        echo "Error: Couldn't add the user $user to groups $csv_groups, usermod exited with error code $?."
        exit 1
    }
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

    pip install "${packages[@]}" || {
        echo "Error: Installing pip packages failed with error code $?."
        exit 1
    }
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
    
    check_required_dir ~/projects/dotfiles
    check_required_dir ~/projects/dockerfiles

    sudo apt-get update || {
        echo "Error: apt-get update failed with error code $?."
        exit 1
    }

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
    );
    local -r dev_packages=(
        gcc
        g++
        make
        python-pip
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
    );
    local -r extra_packages=(
        apt-file
        lm-sensors
    );
    local -r laptop_packages=(
        powertop
        wireless-tools
    );
    local -r pip_packages=(
        ranger-fm
        youtube-dl
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
    local -r extra_groups=(
        audio
        docker
    );

    add_user_to_groups "$USER" "${extra_groups[@]}"

    # Build docker images from ~/projects/dockerfiles subdirectories
    local -r docker_files=($(
        find ~/projects/dockerfiles \
            -maxdepth 1 \
            -mindepth 1 \
            -type d \
            -not -path */.git \
            -not -path */*-todo | sort
    ))

    build_docker_images "${docker_files[@]}"

    local -A configs=(
        [".bashrc"]=~/.bashrc
        [".inputrc"]=~/.inputrc
        [".screenrc"]=~/.screenrc
        [".vimrc"]=~/.vimrc
        [".config/i3"]=~/.config/i3
        [".urxvt"]=~/.urxvt
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

    if [[ $COMPUTER_TYPE == "desktop" ]]; then
        touch ~/.computer-desktop || {
            echo "Error: Unable to create ~/.computer-desktop, touch failed with error code $?."
            exit 1
        };
    elif [[ $COMPUTER_TYPE == "laptop" ]]; then
        touch ~/.computer-laptop || {
            echo "Error: Unable to create ~/.computer-desktop, touch failed with error code $?."
            exit 1
        };
    fi

    # TODO: setup rc.local and iptables rules
    # TODO: autorun powertop on a laptop

    sudo timedatectl set-timezone UTC || {
        echo "Error: Setting timezone to UTC failed with error code $?."
        exit 1;
    }

    echo "Your $COMPUTER_TYPE computer has been installed."
}

main "$@"

