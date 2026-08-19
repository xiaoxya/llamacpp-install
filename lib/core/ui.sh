#!/usr/bin/env bash

readonly UI_TITLE="llama.cpp 部署"
readonly UI_WIDTH=66

ui_content_height() {
    local content="$1" padding="${2:-5}" min="${3:-7}" max="${4:-20}"
    local lines height
    lines="$(awk 'END { print NR }' <<< "$content")"
    height=$((lines + padding))
    ((height < min)) && height="$min"
    ((height > max)) && height="$max"
    printf '%s\n' "$height"
}

ui_init() {
    local requested="${1:-auto}"
    case "$requested" in
        auto)
            if command_exists whiptail; then
                UI_MODE=whiptail
            elif command_exists dialog; then
                UI_MODE=dialog
            else
                UI_MODE=text
            fi
            ;;
        whiptail|dialog)
            command_exists "$requested" || die "找不到界面工具：$requested"
            UI_MODE="$requested"
            ;;
        text) UI_MODE=text ;;
        *) die "不支持的界面模式：$requested" ;;
    esac
}

ui_menu() {
    local prompt="$1" default_item="$2"
    shift 2
    local -a items=("$@")
    local item_count menu_height
    item_count=$((${#items[@]} / 2))
    menu_height=$((item_count + 7))

    case "$UI_MODE" in
        whiptail)
            whiptail --title "$UI_TITLE" --ok-button "选择" --cancel-button "退出" \
                --notags --default-item "$default_item" \
                --menu "$prompt" "$menu_height" "$UI_WIDTH" "$item_count" \
                "${items[@]}" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --stdout --title "$UI_TITLE" --ok-label "选择" --cancel-label "退出" \
                --no-tags --default-item "$default_item" \
                --menu "$prompt" "$menu_height" "$UI_WIDTH" "$item_count" \
                "${items[@]}"
            ;;
        text)
            ui_text_menu "$prompt" "$default_item" "${items[@]}"
            ;;
    esac
}

ui_text_menu() {
    local prompt="$1" default_item="$2"
    shift 2
    local -a items=("$@")
    local index=1 answer i default_index=1

    printf '┌─ %s · %s\n' "$UI_TITLE" "$prompt" >&2
    for ((i = 0; i < ${#items[@]}; i += 2)); do
        [[ "${items[i]}" == "$default_item" ]] && default_index="$index"
        printf '│ %d  %s\n' "$index" "${items[i + 1]}" >&2
        ((index += 1))
    done

    if [[ ! -t 0 ]]; then
        printf '%s\n' "$default_item"
        return
    fi

    read -r -p "└─ 选择 [默认 $default_index] › " answer
    if [[ -z "$answer" ]]; then
        printf '%s\n' "$default_item"
    elif [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#items[@]} / 2)); then
        printf '%s\n' "${items[(answer - 1) * 2]}"
    else
        die "无效选择：$answer"
    fi
}

ui_input() {
    local prompt="$1" default_value="$2" result
    case "$UI_MODE" in
        whiptail)
            whiptail --title "$UI_TITLE" --ok-button "确认" --cancel-button "返回" \
                --inputbox "$prompt" 8 "$UI_WIDTH" "$default_value" \
                3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --stdout --title "$UI_TITLE" --ok-label "确认" --cancel-label "返回" \
                --inputbox "$prompt" 8 "$UI_WIDTH" "$default_value"
            ;;
        text)
            if [[ ! -t 0 ]]; then
                printf '%s\n' "$default_value"
                return
            fi
            read -r -p "› $prompt [$default_value]：" result
            printf '%s\n' "${result:-$default_value}"
            ;;
    esac
}

ui_confirm() {
    local prompt="$1"
    prompt="${prompt//\\n/$'\n'}"
    local height
    height="$(ui_content_height "$prompt" 5 7 14)"
    case "$UI_MODE" in
        whiptail)
            whiptail --title "确认 · $UI_TITLE" --yes-button "继续" --no-button "返回" \
                --yesno "$prompt" "$height" "$UI_WIDTH"
            ;;
        dialog)
            dialog --title "确认 · $UI_TITLE" --yes-label "继续" --no-label "返回" \
                --yesno "$prompt" "$height" "$UI_WIDTH"
            ;;
        text)
            local answer
            [[ -t 0 ]] || return 1
            printf '┌─ 确认\n%s\n' "$prompt" >&2
            read -r -p "└─ 继续？[y/N] › " answer
            [[ "$answer" =~ ^[Yy]$ ]]
            ;;
    esac
}

ui_message() {
    local message="$1"
    message="${message//\\n/$'\n'}"
    local height
    height="$(ui_content_height "$message" 5 7 20)"
    case "$UI_MODE" in
        whiptail)
            whiptail --title "$UI_TITLE" --ok-button "确定" \
                --msgbox "$message" "$height" "$UI_WIDTH"
            ;;
        dialog)
            dialog --title "$UI_TITLE" --ok-label "确定" \
                --msgbox "$message" "$height" "$UI_WIDTH"
            ;;
        text) printf '┌─ %s\n%s\n└─\n' "$UI_TITLE" "$message" ;;
    esac
}
