# Setting Amazon Linux on EC2 G4dn.xlarge for Remote Access: Desktop, NVIDIA Drivers, CUDA. 

This repository provides a comprehensive Bash script, `setup_research_env.sh`, to bootstrap an Amazon EC2 instance for data research. It configures a desktop GUI, NICE DCV server, NVIDIA drivers & CUDA, Python3 environment, JupyterLab, and core machine learning libraries (PyTorch, TensorFlow, Transformers, OpenCV, MediaPipe).

## Features

- **Amazon Linux 2 & 2023** support
- **Desktop GUI** (MATE on AL2, GNOME on AL2023)
- **NICE DCV** installation & secure configuration
- **Firewall** configuration to open port 8443
- **NVIDIA** driver installation via DKMS or Amazon Linux extras
- **CUDA toolkit** installation and automatic profile script
- **Python3** and **pip** installation
- **Machine learning stack**: PyTorch (CUDA), TensorFlow, Transformers, Datasets, OpenCV, MediaPipe
- **JupyterLab** setup for interactive notebooks
- **Environment health checks** (`check-env-install` mode)

## Prerequisites

- An AWS EC2 instance (g4dn.xlarge recommended) running Amazon Linux 2 or Amazon Linux 2023
- Root (sudo) access
- Security group allowing inbound TCP port 8443 and your JupyterLab port (default 8888)
- Internet connectivity to AWS package repositories and PyPI indices

## Quickstart

1. **Clone the repository**
   ```bash
   git clone git@github.com:<your-username>/research-setup.git
   cd research-setup
   ```

2. **Run the installer**
   ```bash
   chmod +x setup_research_env.sh
   sudo ./setup_research_env.sh
   ```

3. **Reboot for GPU & DCV**
   ```bash
   sudo reboot
   ```

4. **Verify environment**
   ```bash
   sudo ./setup_research_env.sh check-env-install
   ```

5. **Launch JupyterLab**
   ```bash
   jupyter lab --ip=0.0.0.0 --port=8888 --no-browser
   ```

## Usage

- **Installation mode** (default):
  ```bash
  sudo ./setup_research_env.sh
  ```

- **Check mode** (verify health):
  ```bash
  sudo ./setup_research_env.sh check-env-install
  ```

## Customization

- Edit `setup_research_env.sh` to tweak:
  - Desktop session script path
  - DCV configuration (`/etc/dcv/dcv.conf`)
  - CUDA version or extras channel
  - ML library versions

## License

This project is provided under the [MIT License](LICENSE).


