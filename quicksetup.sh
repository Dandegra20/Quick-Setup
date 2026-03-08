#!/bin/bash

# ============================================================
#   QuickSetup - Instalación automática de drivers en Linux
#   Compatible con: Ubuntu/Debian, Fedora/RHEL, Arch Linux
# ============================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # Sin color

# Variables globales
DISTRO=""
PKG_MANAGER=""
LOG_FILE="/var/log/driver_manager.log"
DETECTED_GPU=""
DETECTED_WIFI=""
DETECTED_AUDIO=""
DETECTED_BLUETOOTH=""
KERNEL_STATUS=""       # ok | warning | critical
KERNEL_ISSUES=()       # lista de problemas detectados
KERNEL_SUGGESTIONS=()  # lista de sugerencias

# ─────────────────────────────────────────────
#  UTILIDADES
# ─────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║          ⚡ QuickSetup v1.0                  ║"
    echo "  ║   Instalación automática de drivers          ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BLUE}${BOLD}━━━ $1 ━━━${NC}"
}

success() { echo -e "  ${GREEN}✔${NC} $1"; log "OK: $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC}  $1"; log "WARN: $1"; }
error()   { echo -e "  ${RED}✘${NC} $1"; log "ERROR: $1"; }
info()    { echo -e "  ${CYAN}ℹ${NC}  $1"; log "INFO: $1"; }

press_enter() {
    echo -e "\n  ${YELLOW}Presiona ENTER para continuar...${NC}"
    read -r
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n${RED}${BOLD}  ✘ Este programa debe ejecutarse como root (sudo).${NC}"
        echo -e "  Uso: ${CYAN}sudo bash driver_manager.sh${NC}\n"
        exit 1
    fi
}

# ─────────────────────────────────────────────
#  DETECTAR DISTRIBUCIÓN
# ─────────────────────────────────────────────

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="$NAME"
        DISTRO_ID="$ID"
        DISTRO_LIKE="${ID_LIKE:-}"
    fi

    if command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
        DISTRO="debian"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        DISTRO="fedora"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        DISTRO="rhel"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        DISTRO="arch"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
        DISTRO="suse"
    else
        DISTRO="unknown"
        PKG_MANAGER="unknown"
    fi
}

install_pkg() {
    local pkg="$1"
    log "Instalando: $pkg"
    case "$PKG_MANAGER" in
        apt)    apt-get install -y "$pkg" &>/dev/null ;;
        dnf)    dnf install -y "$pkg" &>/dev/null ;;
        yum)    yum install -y "$pkg" &>/dev/null ;;
        pacman) pacman -S --noconfirm "$pkg" &>/dev/null ;;
        zypper) zypper install -y "$pkg" &>/dev/null ;;
        *)      error "Gestor de paquetes no soportado"; return 1 ;;
    esac
}

update_repos() {
    info "Actualizando repositorios..."
    case "$PKG_MANAGER" in
        apt)    apt-get update -qq &>/dev/null ;;
        dnf)    dnf check-update -q &>/dev/null; true ;;
        yum)    yum check-update -q &>/dev/null; true ;;
        pacman) pacman -Sy &>/dev/null ;;
        zypper) zypper refresh &>/dev/null ;;
    esac
}

# ─────────────────────────────────────────────
#  DETECCIÓN DE HARDWARE
# ─────────────────────────────────────────────

detect_hardware() {
    print_header
    print_section "Detectando hardware del sistema"
    echo ""

    # CPU
    CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    [ -z "$CPU" ] && CPU="No detectado"
    info "CPU: ${BOLD}$CPU${NC}"

    # GPU
    if command -v lspci &>/dev/null; then
        GPU_LINE=$(lspci | grep -iE 'vga|3d|display' | head -1)
        if echo "$GPU_LINE" | grep -qi "nvidia"; then
            DETECTED_GPU="nvidia"
        elif echo "$GPU_LINE" | grep -qi "amd\|radeon\|ati"; then
            DETECTED_GPU="amd"
        elif echo "$GPU_LINE" | grep -qi "intel"; then
            DETECTED_GPU="intel"
        elif echo "$GPU_LINE" | grep -qi "vmware\|virtualbox\|qemu"; then
            DETECTED_GPU="virtual"
        else
            DETECTED_GPU="generic"
        fi
        GPU_DESC=$(echo "$GPU_LINE" | sed 's/.*: //')
        info "GPU: ${BOLD}${GPU_DESC:-No detectada}${NC} → Driver: ${GREEN}$DETECTED_GPU${NC}"
    else
        warning "lspci no disponible, GPU no detectada"
        DETECTED_GPU="generic"
    fi

    # Tarjeta de red / WiFi
    if command -v lspci &>/dev/null; then
        WIFI_LINE=$(lspci | grep -i "network\|wireless\|wifi\|wi-fi" | head -1)
        if echo "$WIFI_LINE" | grep -qi "intel"; then
            DETECTED_WIFI="intel"
        elif echo "$WIFI_LINE" | grep -qi "broadcom\|bcm"; then
            DETECTED_WIFI="broadcom"
        elif echo "$WIFI_LINE" | grep -qi "realtek\|rtl"; then
            DETECTED_WIFI="realtek"
        elif echo "$WIFI_LINE" | grep -qi "atheros\|qca\|qualcomm"; then
            DETECTED_WIFI="atheros"
        elif [ -n "$WIFI_LINE" ]; then
            DETECTED_WIFI="generic"
        else
            DETECTED_WIFI="none"
        fi
        WIFI_DESC=$(echo "$WIFI_LINE" | sed 's/.*: //')
        if [ "$DETECTED_WIFI" != "none" ]; then
            info "WiFi: ${BOLD}${WIFI_DESC}${NC} → Driver: ${GREEN}$DETECTED_WIFI${NC}"
        else
            info "WiFi: ${YELLOW}No detectada (puede ser USB o integrada)${NC}"
        fi
    fi

    # Audio
    if command -v lspci &>/dev/null; then
        AUDIO_LINE=$(lspci | grep -i "audio\|sound\|multimedia" | head -1)
        if echo "$AUDIO_LINE" | grep -qi "intel"; then
            DETECTED_AUDIO="intel-hda"
        elif echo "$AUDIO_LINE" | grep -qi "nvidia"; then
            DETECTED_AUDIO="nvidia-hda"
        elif echo "$AUDIO_LINE" | grep -qi "amd\|ati\|realtek"; then
            DETECTED_AUDIO="amd-audio"
        else
            DETECTED_AUDIO="generic"
        fi
        AUDIO_DESC=$(echo "$AUDIO_LINE" | sed 's/.*: //')
        info "Audio: ${BOLD}${AUDIO_DESC:-Integrado}${NC} → Driver: ${GREEN}$DETECTED_AUDIO${NC}"
    fi

    # Bluetooth
    if command -v lsusb &>/dev/null; then
        BT_LINE=$(lsusb | grep -i "bluetooth" | head -1)
        [ -n "$BT_LINE" ] && DETECTED_BLUETOOTH="yes" || DETECTED_BLUETOOTH="no"
        if [ "$DETECTED_BLUETOOTH" = "yes" ]; then
            info "Bluetooth: ${GREEN}Detectado${NC}"
        else
            info "Bluetooth: ${YELLOW}No detectado${NC}"
        fi
    fi

    # RAM
    RAM=$(free -h | awk '/^Mem:/{print $2}')
    info "RAM total: ${BOLD}$RAM${NC}"

    # Arquitectura
    ARCH=$(uname -m)
    info "Arquitectura: ${BOLD}$ARCH${NC}"

    # Kernel
    KERNEL=$(uname -r)
    info "Kernel: ${BOLD}$KERNEL${NC}"

    echo ""
    success "Detección completada"
    press_enter
}

# ─────────────────────────────────────────────
#  INSTALADORES DE DRIVERS
# ─────────────────────────────────────────────

install_gpu_driver() {
    print_header
    print_section "Instalación de drivers GPU"
    echo ""
    info "GPU detectada: ${BOLD}$DETECTED_GPU${NC}"
    echo ""

    case "$DETECTED_GPU" in
        nvidia)
            echo -e "  ${CYAN}Selecciona el tipo de driver NVIDIA:${NC}"
            echo "    1) Drivers propietarios (recomendado, mejor rendimiento)"
            echo "    2) Driver libre Nouveau"
            echo "    3) Cancelar"
            echo ""
            read -rp "  Opción: " gpu_opt
            case "$gpu_opt" in
                1)
                    info "Instalando drivers NVIDIA propietarios..."
                    update_repos
                    case "$PKG_MANAGER" in
                        apt)
                            install_pkg "nvidia-detect" 2>/dev/null
                            install_pkg "nvidia-driver" || install_pkg "nvidia-current"
                            ;;
                        dnf)
                            dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm &>/dev/null
                            dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm &>/dev/null
                            install_pkg "akmod-nvidia"
                            install_pkg "xorg-x11-drv-nvidia-cuda"
                            ;;
                        pacman)
                            install_pkg "nvidia"
                            install_pkg "nvidia-utils"
                            install_pkg "nvidia-settings"
                            ;;
                    esac
                    success "Drivers NVIDIA instalados correctamente"
                    warning "Se recomienda reiniciar el sistema"
                    ;;
                2)
                    info "El driver Nouveau ya viene incluido en el kernel de Linux"
                    install_pkg "xserver-xorg-video-nouveau" 2>/dev/null || true
                    success "Driver Nouveau verificado"
                    ;;
                3) return ;;
            esac
            ;;

        amd)
            info "Instalando drivers AMD/ATI..."
            update_repos
            case "$PKG_MANAGER" in
                apt)
                    install_pkg "firmware-amd-graphics" 2>/dev/null || true
                    install_pkg "xserver-xorg-video-amdgpu" 2>/dev/null || true
                    install_pkg "mesa-vulkan-drivers" 2>/dev/null || true
                    ;;
                dnf)
                    install_pkg "mesa-dri-drivers"
                    install_pkg "mesa-vulkan-drivers"
                    install_pkg "xorg-x11-drv-amdgpu"
                    ;;
                pacman)
                    install_pkg "mesa"
                    install_pkg "vulkan-radeon"
                    install_pkg "xf86-video-amdgpu"
                    ;;
            esac
            success "Drivers AMD instalados correctamente"
            ;;

        intel)
            info "Instalando drivers Intel Graphics..."
            update_repos
            case "$PKG_MANAGER" in
                apt)
                    install_pkg "intel-media-va-driver" 2>/dev/null || true
                    install_pkg "i965-va-driver" 2>/dev/null || true
                    install_pkg "mesa-utils" 2>/dev/null || true
                    ;;
                dnf)
                    install_pkg "intel-media-driver"
                    install_pkg "mesa-dri-drivers"
                    ;;
                pacman)
                    install_pkg "mesa"
                    install_pkg "vulkan-intel"
                    install_pkg "intel-media-driver"
                    ;;
            esac
            success "Drivers Intel instalados correctamente"
            ;;

        virtual)
            info "Sistema virtualizado detectado. Instalando Guest Additions/Tools..."
            case "$PKG_MANAGER" in
                apt) install_pkg "open-vm-tools" 2>/dev/null; install_pkg "virtualbox-guest-utils" 2>/dev/null || true ;;
                dnf) install_pkg "open-vm-tools" 2>/dev/null; true ;;
                pacman) install_pkg "open-vm-tools" 2>/dev/null; true ;;
            esac
            success "Herramientas de virtualización instaladas"
            ;;

        *)
            info "Instalando drivers de video genéricos..."
            case "$PKG_MANAGER" in
                apt) install_pkg "xserver-xorg-video-fbdev" 2>/dev/null || true ;;
                dnf) install_pkg "xorg-x11-drv-fbdev" 2>/dev/null || true ;;
                pacman) install_pkg "xf86-video-fbdev" 2>/dev/null || true ;;
            esac
            success "Drivers genéricos instalados"
            ;;
    esac

    press_enter
}

install_wifi_driver() {
    print_header
    print_section "Instalación de drivers WiFi"
    echo ""
    info "Chipset WiFi detectado: ${BOLD}$DETECTED_WIFI${NC}"
    echo ""

    if [ "$DETECTED_WIFI" = "none" ]; then
        warning "No se detectó tarjeta WiFi PCI."
        info "Si tienes un adaptador USB, conéctalo ahora."
        echo ""
    fi

    update_repos

    case "$DETECTED_WIFI" in
        intel)
            info "Instalando firmware Intel WiFi..."
            case "$PKG_MANAGER" in
                apt)    install_pkg "firmware-iwlwifi" 2>/dev/null || install_pkg "linux-firmware" ;;
                dnf)    install_pkg "iwl7265-firmware" 2>/dev/null; install_pkg "linux-firmware" ;;
                pacman) install_pkg "linux-firmware" ;;
            esac
            success "Firmware Intel WiFi instalado"
            ;;
        broadcom)
            info "Instalando drivers Broadcom WiFi..."
            case "$PKG_MANAGER" in
                apt)
                    install_pkg "bcmwl-kernel-source" 2>/dev/null || install_pkg "broadcom-sta-dkms"
                    ;;
                dnf)
                    install_pkg "broadcom-wl" 2>/dev/null || true
                    ;;
                pacman)
                    install_pkg "broadcom-wl-dkms"
                    ;;
            esac
            success "Drivers Broadcom instalados"
            warning "Puede requerir reinicio para activarse"
            ;;
        realtek)
            info "Instalando drivers Realtek WiFi..."
            case "$PKG_MANAGER" in
                apt)    install_pkg "firmware-realtek" 2>/dev/null; install_pkg "linux-firmware" ;;
                dnf)    install_pkg "linux-firmware" ;;
                pacman) install_pkg "linux-firmware" ;;
            esac
            success "Firmware Realtek instalado"
            ;;
        atheros)
            info "Instalando firmware Atheros/Qualcomm..."
            case "$PKG_MANAGER" in
                apt)    install_pkg "firmware-atheros" 2>/dev/null; install_pkg "linux-firmware" ;;
                dnf)    install_pkg "linux-firmware" ;;
                pacman) install_pkg "linux-firmware" ;;
            esac
            success "Firmware Atheros instalado"
            ;;
        *)
            info "Instalando firmware genérico de red inalámbrica..."
            install_pkg "linux-firmware" 2>/dev/null || true
            success "Firmware genérico instalado"
            ;;
    esac

    # Reiniciar módulos de red
    info "Recargando módulos de red..."
    modprobe -r iwlwifi 2>/dev/null; modprobe iwlwifi 2>/dev/null || true

    press_enter
}

install_audio_driver() {
    print_header
    print_section "Instalación de drivers de Audio"
    echo ""
    info "Hardware de audio detectado: ${BOLD}$DETECTED_AUDIO${NC}"
    echo ""

    update_repos

    case "$PKG_MANAGER" in
        apt)
            install_pkg "alsa-base"
            install_pkg "alsa-utils"
            install_pkg "pulseaudio" 2>/dev/null || true
            install_pkg "pipewire" 2>/dev/null || true
            install_pkg "firmware-sof-signed" 2>/dev/null || true
            ;;
        dnf)
            install_pkg "alsa-utils"
            install_pkg "pulseaudio"
            install_pkg "alsa-firmware"
            ;;
        pacman)
            install_pkg "alsa-utils"
            install_pkg "pipewire"
            install_pkg "pipewire-pulse"
            install_pkg "wireplumber"
            ;;
    esac

    # Recargar ALSA
    if command -v alsactl &>/dev/null; then
        alsactl init &>/dev/null || true
    fi

    success "Drivers de audio instalados correctamente"
    press_enter
}

install_bluetooth_driver() {
    print_header
    print_section "Instalación de drivers Bluetooth"
    echo ""

    update_repos

    case "$PKG_MANAGER" in
        apt)
            install_pkg "bluetooth"
            install_pkg "bluez"
            install_pkg "bluez-tools" 2>/dev/null || true
            install_pkg "blueman" 2>/dev/null || true
            ;;
        dnf)
            install_pkg "bluez"
            install_pkg "bluez-tools"
            ;;
        pacman)
            install_pkg "bluez"
            install_pkg "bluez-utils"
            ;;
    esac

    systemctl enable bluetooth &>/dev/null && systemctl start bluetooth &>/dev/null || true
    success "Bluetooth instalado y activado"
    press_enter
}

install_printer_driver() {
    print_header
    print_section "Instalación de soporte para Impresoras"
    echo ""

    update_repos

    case "$PKG_MANAGER" in
        apt)
            install_pkg "cups"
            install_pkg "cups-client"
            install_pkg "hplip" 2>/dev/null || true
            install_pkg "printer-driver-all" 2>/dev/null || true
            ;;
        dnf)
            install_pkg "cups"
            install_pkg "hplip"
            ;;
        pacman)
            install_pkg "cups"
            install_pkg "hplip"
            install_pkg "gutenprint"
            ;;
    esac

    systemctl enable cups &>/dev/null && systemctl start cups &>/dev/null || true
    success "Sistema de impresión CUPS instalado"
    info "Accede a http://localhost:631 para gestionar impresoras"
    press_enter
}

install_all_drivers() {
    print_header
    print_section "Instalación COMPLETA de todos los drivers"
    echo ""
    warning "Se instalarán todos los drivers detectados automáticamente."
    read -rp "  ¿Confirmar? (s/N): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        update_repos
        install_gpu_driver
        install_wifi_driver
        install_audio_driver
        [ "$DETECTED_BLUETOOTH" = "yes" ] && install_bluetooth_driver
        install_printer_driver
        print_header
        success "¡Instalación completa finalizada!"
        warning "Se recomienda reiniciar el sistema para aplicar todos los cambios."
    else
        info "Instalación cancelada."
    fi
    press_enter
}

# ─────────────────────────────────────────────
#  DIAGNÓSTICO
# ─────────────────────────────────────────────

show_diagnostics() {
    print_header
    print_section "Diagnóstico del sistema"
    echo ""

    # Módulos del kernel activos
    info "${BOLD}Módulos de kernel activos (GPU/Red/Audio):${NC}"
    lsmod | grep -iE "nvidia|nouveau|amdgpu|radeon|i915|iwlwifi|rtl|brcm|ath|snd" | awk '{print "    → " $1}' || echo "    (ninguno detectado)"

    echo ""

    # Dispositivos PCI
    if command -v lspci &>/dev/null; then
        info "${BOLD}Dispositivos PCI relevantes:${NC}"
        lspci | grep -iE "vga|audio|network|wireless|bluetooth" | while read -r line; do
            echo "    → $line"
        done
    fi

    echo ""

    # Estado de servicios
    info "${BOLD}Estado de servicios:${NC}"
    for svc in bluetooth cups NetworkManager pulseaudio; do
        if systemctl is-active "$svc" &>/dev/null; then
            echo -e "    ${GREEN}●${NC} $svc: activo"
        elif systemctl list-units --all | grep -q "$svc"; then
            echo -e "    ${RED}●${NC} $svc: inactivo"
        fi
    done

    echo ""
    info "Log guardado en: ${BOLD}$LOG_FILE${NC}"
    press_enter
}

# ─────────────────────────────────────────────
#  DIAGNÓSTICO DE COMPATIBILIDAD DEL KERNEL
# ─────────────────────────────────────────────

check_kernel_compatibility() {
    print_header
    print_section "Diagnóstico de compatibilidad del Kernel"
    echo ""

    KERNEL_STATUS="ok"
    KERNEL_ISSUES=()
    KERNEL_SUGGESTIONS=()

    KERNEL_FULL=$(uname -r)
    ARCH=$(uname -m)
    KERNEL_MAJOR=$(uname -r | cut -d. -f1)
    KERNEL_MINOR=$(uname -r | cut -d. -f2)
    KERNEL_NUM=$((KERNEL_MAJOR * 100 + KERNEL_MINOR))

    info "Kernel actual:   ${BOLD}$KERNEL_FULL${NC}"
    info "Arquitectura:    ${BOLD}$ARCH${NC}"
    echo ""

    # ── 1. Arquitectura 32 bits ──────────────────────────────
    if [[ "$ARCH" == "i386" || "$ARCH" == "i686" ]]; then
        KERNEL_ISSUES+=("Arquitectura 32 bits detectada (${ARCH})")
        KERNEL_SUGGESTIONS+=("Muchos drivers modernos ya no tienen soporte para 32 bits. Considera migrar a 64 bits si el hardware lo permite.")
        KERNEL_STATUS="warning"
        echo -e "  ${YELLOW}⚠${NC}  Arquitectura ${BOLD}32 bits${NC}: soporte limitado en kernels modernos"
    else
        echo -e "  ${GREEN}✔${NC}  Arquitectura ${BOLD}64 bits${NC}: compatible con todos los drivers actuales"
    fi

    # ── 2. Versión del kernel demasiado antigua ──────────────
    if (( KERNEL_NUM < 415 )); then
        KERNEL_ISSUES+=("Kernel muy antiguo: $KERNEL_FULL (< 4.15)")
        KERNEL_SUGGESTIONS+=("Actualiza el kernel con: apt install linux-image-amd64  (en Debian/Ubuntu)")
        KERNEL_STATUS="critical"
        echo -e "  ${RED}✘${NC}  Kernel ${BOLD}muy antiguo${NC} (${KERNEL_FULL}): drivers modernos de GPU y WiFi pueden NO funcionar"
    elif (( KERNEL_NUM < 500 )); then
        KERNEL_ISSUES+=("Kernel antiguo: $KERNEL_FULL (< 5.0)")
        KERNEL_SUGGESTIONS+=("Se recomienda actualizar al menos al kernel 5.x para mejor compatibilidad con drivers.")
        KERNEL_STATUS="warning"
        echo -e "  ${YELLOW}⚠${NC}  Kernel ${BOLD}antiguo${NC} (${KERNEL_FULL}): algunos drivers pueden tener problemas"
    elif (( KERNEL_NUM < 515 )); then
        echo -e "  ${YELLOW}⚠${NC}  Kernel ${BOLD}5.x${NC} (${KERNEL_FULL}): funcional, pero existen versiones más estables"
    else
        echo -e "  ${GREEN}✔${NC}  Kernel ${BOLD}moderno${NC} (${KERNEL_FULL}): excelente compatibilidad con drivers"
    fi

    # ── 3. Cabeceras del kernel instaladas ───────────────────
    HEADERS_PKG="linux-headers-$(uname -r)"
    if dpkg -l "$HEADERS_PKG" &>/dev/null 2>&1 || \
       rpm -q "kernel-headers" &>/dev/null 2>&1 || \
       pacman -Q linux-headers &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✔${NC}  Cabeceras del kernel: ${BOLD}instaladas${NC} (necesarias para compilar drivers)"
    else
        KERNEL_ISSUES+=("Cabeceras del kernel no instaladas")
        KERNEL_SUGGESTIONS+=("Instala las cabeceras con: apt install linux-headers-\$(uname -r)")
        [ "$KERNEL_STATUS" != "critical" ] && KERNEL_STATUS="warning"
        echo -e "  ${YELLOW}⚠${NC}  Cabeceras del kernel: ${BOLD}NO instaladas${NC} (necesarias para DKMS y drivers compilados)"
    fi

    # ── 4. DKMS disponible ───────────────────────────────────
    if command -v dkms &>/dev/null; then
        echo -e "  ${GREEN}✔${NC}  DKMS: ${BOLD}disponible${NC} (permite recompilar drivers automáticamente)"
    else
        KERNEL_ISSUES+=("DKMS no está instalado")
        KERNEL_SUGGESTIONS+=("Instala DKMS con: apt install dkms  — es necesario para drivers Broadcom, NVIDIA y otros.")
        [ "$KERNEL_STATUS" != "critical" ] && KERNEL_STATUS="warning"
        echo -e "  ${YELLOW}⚠${NC}  DKMS: ${BOLD}no disponible${NC} (algunos drivers no podrán compilarse)"
    fi

    # ── 5. Secure Boot ───────────────────────────────────────
    if command -v mokutil &>/dev/null; then
        SB_STATE=$(mokutil --sb-state 2>/dev/null)
        if echo "$SB_STATE" | grep -qi "enabled"; then
            KERNEL_ISSUES+=("Secure Boot está ACTIVADO")
            KERNEL_SUGGESTIONS+=("Secure Boot puede bloquear drivers sin firma (NVIDIA, Broadcom). Puedes desactivarlo en la BIOS/UEFI o firmar los módulos manualmente.")
            [ "$KERNEL_STATUS" != "critical" ] && KERNEL_STATUS="warning"
            echo -e "  ${YELLOW}⚠${NC}  Secure Boot: ${BOLD}ACTIVADO${NC} — puede bloquear drivers de terceros (NVIDIA, Broadcom)"
        else
            echo -e "  ${GREEN}✔${NC}  Secure Boot: ${BOLD}desactivado${NC} — drivers de terceros pueden cargarse sin restricciones"
        fi
    else
        echo -e "  ${CYAN}ℹ${NC}  Secure Boot: no se pudo verificar (mokutil no disponible)"
    fi

    # ── 6. PAE en 32 bits ────────────────────────────────────
    if [[ "$ARCH" == "i686" ]]; then
        if grep -q "pae" /proc/cpuinfo 2>/dev/null; then
            echo -e "  ${GREEN}✔${NC}  PAE: ${BOLD}soportado${NC} — puede usar kernel PAE para acceder a más de 4 GB RAM"
        else
            KERNEL_ISSUES+=("CPU 32 bits sin soporte PAE")
            KERNEL_SUGGESTIONS+=("Esta CPU no soporta PAE. El límite de RAM es 4 GB y el soporte de software es muy reducido.")
            KERNEL_STATUS="critical"
            echo -e "  ${RED}✘${NC}  PAE: ${BOLD}no soportado${NC} — RAM limitada a 4 GB, compatibilidad muy reducida"
        fi
    fi

    # ── 7. Resumen final ─────────────────────────────────────
    echo ""
    print_section "Resumen"
    echo ""

    if [ ${#KERNEL_ISSUES[@]} -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}✔ Todo en orden — el kernel es totalmente compatible con los drivers disponibles.${NC}"
    else
        case "$KERNEL_STATUS" in
            warning)
                echo -e "  ${YELLOW}${BOLD}⚠  Se detectaron advertencias que pueden afectar la instalación de drivers:${NC}"
                ;;
            critical)
                echo -e "  ${RED}${BOLD}✘  Se detectaron problemas críticos de compatibilidad:${NC}"
                ;;
        esac
        echo ""
        for i in "${!KERNEL_ISSUES[@]}"; do
            echo -e "  ${YELLOW}$(( i + 1 )})${NC} ${KERNEL_ISSUES[$i]}"
            echo -e "     ${CYAN}→${NC} ${KERNEL_SUGGESTIONS[$i]}"
            echo ""
        done
    fi

    # ── 8. Ofrecer correcciones automáticas ──────────────────
    if [ ${#KERNEL_ISSUES[@]} -gt 0 ] && [ "$PKG_MANAGER" = "apt" ]; then
        echo ""
        read -rp "  ¿Intentar corregir los problemas automáticamente? (s/N): " fix_opt
        if [[ "$fix_opt" =~ ^[Ss]$ ]]; then
            update_repos
            # Instalar cabeceras si faltan
            if printf '%s\n' "${KERNEL_ISSUES[@]}" | grep -q "Cabeceras"; then
                info "Instalando cabeceras del kernel..."
                install_pkg "linux-headers-$(uname -r)" && success "Cabeceras instaladas" || error "No se pudieron instalar las cabeceras"
            fi
            # Instalar DKMS si falta
            if printf '%s\n' "${KERNEL_ISSUES[@]}" | grep -q "DKMS"; then
                info "Instalando DKMS..."
                install_pkg "dkms" && success "DKMS instalado" || error "No se pudo instalar DKMS"
            fi
            # Actualizar kernel si es muy antiguo
            if printf '%s\n' "${KERNEL_ISSUES[@]}" | grep -q "antiguo"; then
                info "Actualizando kernel..."
                install_pkg "linux-image-amd64" 2>/dev/null || install_pkg "linux-image-generic"
                success "Kernel actualizado — reinicia para aplicar el cambio"
            fi
        fi
    fi

    press_enter
}

# ─────────────────────────────────────────────
#  MENÚ PRINCIPAL
# ─────────────────────────────────────────────

main_menu() {
    while true; do
        print_header

        echo -e "  ${BOLD}Sistema:${NC} ${DISTRO_NAME:-Linux}  |  ${BOLD}Gestor:${NC} $PKG_MANAGER  |  ${BOLD}Kernel:${NC} $(uname -r)"
        echo ""

        echo -e "  ${MAGENTA}${BOLD}┌─────────────────────────────────────────────┐${NC}"
        echo -e "  ${MAGENTA}${BOLD}│             MENÚ PRINCIPAL                  │${NC}"
        echo -e "  ${MAGENTA}${BOLD}└─────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC}  🔍  Detectar hardware del sistema"
        echo -e "  ${CYAN}2)${NC}  🎮  Instalar driver GPU        ${YELLOW}[${DETECTED_GPU:-?}]${NC}"
        echo -e "  ${CYAN}3)${NC}  📶  Instalar driver WiFi       ${YELLOW}[${DETECTED_WIFI:-?}]${NC}"
        echo -e "  ${CYAN}4)${NC}  🔊  Instalar driver Audio      ${YELLOW}[${DETECTED_AUDIO:-?}]${NC}"
        echo -e "  ${CYAN}5)${NC}  🦷  Instalar driver Bluetooth  ${YELLOW}[${DETECTED_BLUETOOTH:-?}]${NC}"
        echo -e "  ${CYAN}6)${NC}  🖨️   Instalar soporte Impresoras"
        echo -e "  ${CYAN}7)${NC}  ⚡  Instalar TODOS los drivers (automático)"
        echo -e "  ${CYAN}8)${NC}  🩺  Diagnóstico del sistema"
        echo -e "  ${CYAN}9)${NC}  🧠  Verificar compatibilidad del Kernel"
        echo ""
        echo -e "  ${RED}0)${NC}  ❌  Salir"
        echo ""
        read -rp "  Selecciona una opción: " choice

        case "$choice" in
            1) detect_hardware ;;
            2) install_gpu_driver ;;
            3) install_wifi_driver ;;
            4) install_audio_driver ;;
            5) install_bluetooth_driver ;;
            6) install_printer_driver ;;
            7) install_all_drivers ;;
            8) show_diagnostics ;;
            9) check_kernel_compatibility ;;
            0)
                echo -e "\n  ${GREEN}¡Hasta luego!${NC}\n"
                exit 0
                ;;
            *)
                error "Opción inválida"
                sleep 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────
#  INICIO
# ─────────────────────────────────────────────

check_root
detect_distro
detect_hardware
main_menu
