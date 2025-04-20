#!/usr/bin/env bash
#
# setup_research_env.sh
# Modes:
#   (no args)           → install everything
#   check-env-install   → validate installation

set -euo pipefail
LOGFILE=/var/log/setup_research_env.log

# ─── Helpers ───────────────────────────────────────────────────────────────────
info()    { printf "\e[1;34m[INFO]\e[0m  %s\n" "$1"; }
ok()      { printf "  \e[1;32m✔\e[0m  %s\n" "$1"; }
err()     { printf "  \e[1;31m✖\e[0m  %s\n" "$1"; }
checkbin(){ printf "\e[1;33m[CHECK]\e[0m %-28s" "$2"; command -v "$1" &>/dev/null && ok "found" || err "MISSING"; }
checkpkg(){ printf "\e[1;33m[CHECK]\e[0m %-28s" "$1"; rpm -q "$1" &>/dev/null && ok "installed" || err "NOT INSTALLED"; }
checksvc(){ printf "\e[1;33m[CHECK]\e[0m %-28s" "$1"; systemctl is-active --quiet "$1" && ok "running" || err "NOT RUNNING"; }
checkport(){
  printf "\e[1;33m[CHECK]\e[0m Port %-25s" "$1"
  if ss -tln | awk '{print $4}' | grep -qE "([0-9.:]+[:.])$1\$"; then ok "listening"; else err "NOT LISTENING"; fi
}
checkpy() { printf "\e[1;33m[CHECK]\e[0m %-28s" "$1"; pip3 show "$1" &>/dev/null && ok "installed" || err "NOT INSTALLED"; }

# ─── Mode detection ─────────────────────────────────────────────────────────────
MODE="install"
[[ "${1:-}" == "check-env-install" ]] && MODE="check"

# ─── INSTALL MODE ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "install" ]]; then
  exec > >(tee -a "$LOGFILE") 2>&1
  echo "==========================================================="
  echo "  INSTALL MODE — Research Environment Setup"
  echo "  Logging to: $LOGFILE"
  echo "==========================================================="

  # 0) Ensure ec2-user
  info "Step 0: ensure ec2-user exists"
  if ! id -u ec2-user &>/dev/null; then useradd -m ec2-user && ok "created ec2-user"; else ok "ec2-user exists"; fi

  # 1) Core tools & OpenGL
  info "Step 1: install core tools + OpenGL"
  yum update -y
  yum install -y git wget curl unzip zip htop tree \
    net-tools iproute lsof bind-utils nmap traceroute telnet \
    openssl mesa-libGL mesa-demos \
    xorg-x11-server-Xorg xterm --allowerasing curl && ok "core tools installed"

  # 2) Desktop GUI
  info "Step 2: install desktop environment"
  . /etc/os-release
  if [[ "$VERSION_ID" == "2" ]]; then
    amazon-linux-extras install -y epel mate-desktop1.x
    yum groupinstall -y "MATE Desktop Environment" && ok "MATE installed"
  elif [[ "$VERSION_ID" == "2023" ]]; then
    dnf groupinstall -y "Server with GUI" && ok "GNOME installed"
  else
    err "Unknown Amazon Linux ($VERSION_ID), skipping GUI"
  fi

  # 3) NICE DCV prerequisites
  info "Step 3: DCV prerequisites"
  rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY && ok "imported DCV GPG key"
  yum install -y pulseaudio-utils && ok "pulseaudio-utils installed"

  # 4) Install NICE DCV server
  info "Step 4: install NICE DCV"
  if [[ "$VERSION_ID" == "2" ]]; then
    yum install -y dcv-server dcv-gl && ok "DCV server + GL via yum"
  else
    TMP=/tmp/dcv-$$ && mkdir -p "$TMP" && cd "$TMP"
    info "  downloading amzn2023 bundle"
    wget -q https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-amzn2023-x86_64.tgz && ok "downloaded DCV bundle"
    tar xzf nice-dcv-amzn2023-x86_64.tgz && cd nice-dcv-*
    dnf install -y nice-dcv-*.rpm && ok "DCV RPMs installed"
    cd / && rm -rf "$TMP"
  fi

  # 5) Configure & start DCV
  info "Step 5: configure & start DCV"
  mkdir -p /etc/dcv-session
  cat >/etc/dcv-session/xfce-session.sh << 'EOF'
#!/bin/bash
exec /usr/bin/xfce4-session
EOF
  chmod +x /etc/dcv-session/xfce-session.sh

  [[ -f /etc/pki/tls/certs/localhost.crt ]] || {
    openssl req -newkey rsa:2048 -nodes \
      -keyout /etc/pki/tls/private/localhost.key \
      -x509 -days 365 \
      -out /etc/pki/tls/certs/localhost.crt \
      -subj "/CN=$(hostname -f)"
    ok "generated TLS cert"
  }

  cat >/etc/dcv/dcv.conf << 'EOF'
[server]
port = 8443
certificate_file = /etc/pki/tls/certs/localhost.crt
private_key_file  = /etc/pki/tls/private/localhost.key

[security]
authentication = "system"
allowed_users  = ec2-user

[session-management]
create-session                = false
enable-gl-in-virtual-sessions = "always-on"

[display]
session_type   = xfce-session
session_script = /etc/dcv-session/xfce-session.sh
target-fps     = 60

[connectivity]
web-port            = 8443
web-url-path        = "/"
enable-quic-frontend = false
quic-port           = 8443
idle-timeout        = 120
EOF

  systemctl enable dcvserver && systemctl start dcvserver && ok "DCV service started"

  # 6a) Open TCP 8443 via iptables
  info "Step 6a: open TCP 8443 via iptables"
  if ! rpm -q iptables-services &>/dev/null; then
    if command -v dnf &>/dev/null; then dnf install -y iptables-services; else yum install -y iptables-services; fi
    ok "iptables-services installed"
  fi
  if ! iptables -C INPUT -p tcp --dport 8443 -j ACCEPT &>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport 8443 -j ACCEPT && ok "iptables rule added for 8443"
  else
    ok "iptables rule for 8443 already present"
  fi
  iptables-save | tee /etc/sysconfig/iptables
  systemctl enable --now iptables && ok "iptables service enabled & started"

  # 7) Force‑upgrade pip & install ML libraries + JupyterLab
  info "Step 7: force‑upgrade pip & install ML libraries"
  python3 -m pip install --upgrade pip setuptools wheel --ignore-installed setuptools && ok "pip setuptools wheel upgraded"
  python3 -m pip install \
    --ignore-installed torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu118 && ok "PyTorch (CUDA) installed"
  python3 -m pip install \
    --ignore-installed tensorflow \
    transformers datasets \
    opencv-python \
    mediapipe \
    jupyterlab && ok "TensorFlow, Transformers, OpenCV, MediaPipe & JupyterLab installed"

  echo
  info "INSTALLATION COMPLETE — please reboot with: sudo reboot"
  exit 0
fi

# ─── CHECK MODE ─────────────────────────────────────────────────────────────────
echo
echo "==========================================================="
echo "  CHECK MODE — verify environment"
echo "==========================================================="
echo

# 0) user
info "Checking Linux user"
if id -u ec2-user &>/dev/null; then ok "ec2-user exists"; else err "ec2-user missing"; fi

# 1) core packages
echo; info "Checking core packages"
for pkg in git wget unzip zip htop tree net-tools iproute lsof bind-utils nmap traceroute telnet openssl mesa-libGL mesa-demos curl; do
  checkpkg "$pkg"
done

# 2) desktop
echo; info "Checking desktop environment"
. /etc/os-release
if [[ "$VERSION_ID" == "2" ]]; then checkbin mate-session "MATE session"; else checkbin gnome-shell "GNOME Shell"; fi
checkbin Xorg "X server"

# 3) DCV
echo; info "Checking Amazon DCV"
checkbin dcvserver "dcvserver binary"
checksvc dcvserver "dcvserver service"
checkport 8443    "8443"

# 4) NVIDIA & CUDA
echo; info "Checking NVIDIA & CUDA"
checkbin nvidia-smi "nvidia-smi"
checkbin nvcc       "nvcc"

# 5) Python & ML packages
echo; info "Checking Python & ML stack"
checkbin python3 "Python3"
checkbin pip3    "pip3"
for lib in torch tensorflow transformers opencv-python mediapipe; do
  checkpy "$lib"
done

# 6) JupyterLab
echo; info "Checking JupyterLab"
checkbin jupyter-lab "JupyterLab"

echo; ok "ALL CHECKS COMPLETE"
exit 0
