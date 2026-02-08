# 🎥 RTSP NVR Dashboard 🔹 Cyber Edition

![Ubuntu](https://img.shields.io/badge/OS-Ubuntu-E95420?logo=ubuntu)
![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Active_Development-yellow)
![WebUI](https://img.shields.io/badge/Web-UI-brightgreen)

A **modern, cyber-themed RTSP NVR Dashboard** with:

- Desktop Qt Dashboard
- Web UI
- RTSP audio/video streaming
- Event timeline
- Audio-triggered recording
- Scheduled recording  
- Cyber aesthetic visuals

---

## 📸 Screenshots

*(Place screenshots here in `docs/screenshots/` folder)*

![Dashboard Mock](docs/screenshots/dashboard.png)
![Timeline Mock](docs/screenshots/timeline.png)
![Settings Mock](docs/screenshots/settings.png)

---

## 🚀 Features

### 📡 Streaming
- Multi-camera RTSP streaming
- Live audio monitoring
- Low-latency playback
- Video and audio recording

### 🎙 Audio Intelligence
- Volume-threshold triggered recording
- Scheduled audio capture
- Audio-only monitoring mode
- Event-based recording

### 📅 Event Timeline
- Unified video + audio events
- Timestamped for playback
- Manual and automated logging

### 🎛️ Web Dashboard
- Live preview tiles
- Event timeline visualization
- Recording controls
- Configuration editor (no CLI needed)

### 🔐 Security
- Local authentication (bcrypt)
- Optional environment-based auth configs
- LAN deployment recommended

### 🛠 Platform Support
- Ubuntu 20.04+ (Desktop/Server)
- Proxmox LXC
- Bare-metal and VM compatible

---

## 📦 Quick Install (Ubuntu)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/OneByJorah/rtsp-nvr-dashboard/main/install.sh)"
