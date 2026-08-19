#!/usr/bin/env bash

pacman_base_packages() {
    printf '%s\n' git cmake ninja base-devel pkgconf curl ca-certificates
}

pacman_cuda_packages() {
    printf '%s\n' cuda
}
