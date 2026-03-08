# ⚡ QuickSetup

> Instalación automática de drivers en Linux — detecta tu hardware y configura todo sin complicaciones.

![Bash](https://img.shields.io/badge/Shell-Bash-green?logo=gnu-bash)
![Linux](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## 🚀 Instalación rápida

```bash
git clone https://github.com/tu-usuario/quicksetup.git
cd quicksetup
chmod +x quicksetup.sh
sudo bash quicksetup.sh
```

O ejecútalo directamente sin clonar:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Dandegra20/quicksetup/main/quicksetup.sh)
```

---

## 🖥️ ¿Qué hace?

QuickSetup detecta automáticamente el hardware de tu ordenador e instala los drivers correctos con un menú interactivo, sin que tengas que buscar nada manualmente.

---

## ✅ Compatibilidad

| Distribución         | Gestor de paquetes |
|----------------------|--------------------|
| Ubuntu / Debian      | apt                |
| Fedora / RHEL        | dnf / yum          |
| Arch Linux / Manjaro | pacman             |
| openSUSE             | zypper             |

---

## 🔧 Funciones del menú

| Opción | Función |
|--------|---------|
| 1 | Detectar hardware del sistema |
| 2 | Instalar driver GPU (NVIDIA / AMD / Intel) |
| 3 | Instalar driver WiFi (Intel / Broadcom / Realtek / Atheros) |
| 4 | Instalar driver Audio (ALSA / PulseAudio / PipeWire) |
| 5 | Instalar driver Bluetooth |
| 6 | Instalar soporte para impresoras (CUPS / HPLIP) |
| 7 | Instalar TODOS los drivers automáticamente |
| 8 | Diagnóstico del sistema |
| 9 | Verificar compatibilidad del Kernel |

---

## 🧠 Verificación del Kernel

QuickSetup analiza si tu kernel es compatible antes de instalar drivers:

- ✔ Detecta arquitectura 32/64 bits
- ✔ Advierte si el kernel es demasiado antiguo (< 4.15 = crítico, < 5.0 = advertencia)
- ✔ Comprueba si las cabeceras del kernel están instaladas
- ✔ Verifica si DKMS está disponible
- ✔ Detecta si Secure Boot puede bloquear drivers de terceros
- ✔ Ofrece corregir los problemas automáticamente

---

## ⚠️ Requisitos

- Linux (cualquier distribución moderna)
- Ejecutar como **root** (`sudo`)
- Conexión a internet para descargar paquetes

---

## 📄 Licencia

MIT — libre para usar, modificar y distribuir.
