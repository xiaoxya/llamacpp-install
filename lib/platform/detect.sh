#!/usr/bin/env bash

detect_os_from_file() {
    local os_release="$1"
    [[ -r "$os_release" ]] || die "无法读取系统信息：$os_release"

    local id="" id_like="" pretty_name=""
    while IFS='=' read -r key value; do
        value="${value%\"}"
        value="${value#\"}"
        case "$key" in
            ID) id="$value" ;;
            ID_LIKE) id_like="$value" ;;
            PRETTY_NAME) pretty_name="$value" ;;
        esac
    done < "$os_release"

    DISTRO_ID="$id"
    DISTRO_NAME="${pretty_name:-$id}"
    case " $id $id_like " in
        *" debian "*|*" ubuntu "*) PACKAGE_FAMILY=apt ;;
        *" arch "*) PACKAGE_FAMILY=pacman ;;
        *) PACKAGE_FAMILY=unsupported ;;
    esac
}

detect_platform() {
    [[ "$(uname -s)" == Linux ]] || die "仅支持 Linux"
    detect_os_from_file "${OS_RELEASE_FILE:-/etc/os-release}"
    [[ "$PACKAGE_FAMILY" != unsupported ]] || \
        die "不支持的发行版：$DISTRO_NAME；首版支持 Debian、Ubuntu 和 Arch Linux"
}
