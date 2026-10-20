
# Getting IPU6 Camera working in Ubuntu 26.04 for Zoom Desktop and Chrome

The block is purely structural: Chrome and Zoom are trying to read standard V4L2 data, but the native IPU6 kernel driver provides raw, unparsed Bayer data over those nodes. Native Ubuntu apps read this correctly because they support libcamera or PipeWire natively, whereas Chrome and Zoom look for a classic video stream. [1, 2]
Since your system already lists Virtual Camera (v4l2loopback) on /dev/video0, we just need to pipe your native libcamera data directly into it using the clean, modern stack. [1]
Step 1: Fix WirePlumber (So PipeWire Maps it Safely)
WirePlumber needs to be explicitly configured to map the kernel's native libcamera nodes so browsers can see them. [1]

## 1: Create a modern WirePlumber override directory in your user profile:

bash:
```mkdir -p ~/.config/wireplumber/wireplumber.conf.d/```

_Use code with caution._
Open a new configuration file:
bash
```nano ~/.config/wireplumber/wireplumber.conf.d/99-libcamera.conf```

Paste the following configuration blocks to map your profiles:
```
wireplumber.profiles = {
  main = {
    monitor.v4l2 = disabled
    monitor.libcamera = optional
  }
}
```

Save and exit (Ctrl+O, Enter, Ctrl+X), then restart your session's media daemons: [1, 2]
bash
```systemctl --user restart wireplumber pipewire```

## 2: Stream Native libcamera into your /dev/video0 Loopback
Because you are running the modern kernel, the GStreamer pipeline uses libcamerasrc (which you have) instead of the defunct icamerasrc. Run this modern pipeline to feed your working hardware stream into the loopback device Chrome and Zoom expect: [1]
bash
```gst-launch-1.0 libcamerasrc ! queue ! videoconvert ! video/x-raw,format=NV12,width=1280,height=720 ! v4l2sink device=/dev/video0```

Keep this terminal window running.

Since the GStreamer loopback command successfully streams the native kernel data to /dev/video0, you can make this solution permanent and automatic by setting up a background systemd user service.
This will automatically start the camera bridge whenever you log into your desktop environment, without requiring sudo or keeping a terminal window open.

### 2.1: Ensure your user can access the loopback device
By default, some systems restrict raw writing access to /dev/video0. Let's ensure your user profile can write to it without root privileges by adding a permanent system rule.

Open a new rule file:
bash
```sudo nano /etc/udev/rules.d/99-v4l2loopback.rules```

Paste this exact line inside:

```KERNEL=="video0", MODE="0666"```

Save and close (Ctrl+O, Enter, then Ctrl+X).

### 2.2: Create a systemd User Service
Instead of a root-level system service, a user service is perfect here because it hooks cleanly into your active desktop session and PipeWire audio/video instances.
Create the user service directory structure:

bash
```mkdir -p ~/.config/systemd/user/```

Open a new service configuration file:

bash
```nano ~/.config/systemd/user/ipu6-bridge.service```

Paste the following configuration block entirely into the file:
```
[Unit]
Description=Intel IPU6 Kernel libcamera to V4L2 Loopback Bridge
After=pipewire.service wireplumber.service
BindsTo=pipewire.service

[Service]
Type=simple
ExecStart=/usr/bin/gst-launch-1.0 libcamerasrc ! queue ! videoconvert ! video/x-raw,format=NV12,width=1280,height=720 ! v4l2sink device=/dev/video0
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

Save and close (Ctrl+O, Enter, then Ctrl+X).

### 2.3: Enable and Start the Service
Close the manual terminal command you had running previously, then execute these commands to register, enable, and kick-start your new automation rule:

bash
```
systemctl --user daemon-reload
systemctl --user enable --now ipu6-bridge.service
```

### 2.4: Add a permanent alias for Zoom (Optional)
Since Chrome is now natively listening via your WebRTC flag setting, it will always see the virtual node. If you want the native Zoom desktop .deb client to automatically launch with its required hook without you typing it out every time, add an alias to your bash environment:
Open your bash configuration file:

bash
```nano ~/.bashrc```

Scroll to the very bottom and add this line:

bash
```alias zoom='libcamerify zoom'```

Save, close, and reload your shell configuration: 
```source ~/.bashrc.```


Your Dell XPS 9320 is now fully configured! Your camera will seamlessly spin up whenever a browser application requests a webcam feed.
To ensure everything settled perfectly in the background, you can run systemctl --user status ipu6-bridge.service . Does it report active (running) without throwing any error lines?

### 2.5: Start the Service

To stop it, run:
systemctl --user stop ipu6-bridge.service

Preventing it from starting automatically
If you want to keep the service installed but stop it from launching automatically when you boot or log in, disable it using:
bash
systemctl --user disable ipu6-bridge.service


### 2.6: Add a permanent alias for Zoom (Optional)

## 3: Quick Commands Summary
Turn off right now: ```systemctl --user stop ipu6-bridge.service```
Turn back on right now: ```systemctl --user start ipu6-bridge.service```
Prevent auto-start on boot: ```systemctl --user disable ipu6-bridge.service```
Allow auto-start on boot again: [find]
Would you like to create a desktop shortcut icon or a terminal alias so you can easily toggle the camera bridge on and off with a single click in the future?

## 4. Can I make the camera bridge only turn on when needed by an app?
Yes, you can absolutely configure it to turn on dynamically only when needed. Right now, the GStreamer background service forces your physical Intel MIPI camera to stream continuously, keeping the hardware awake and the camera LED illuminated 100% of the time.
To make the stream "on-demand," you can swap the current configuration for a highly efficient script that watches your virtual /dev/video0 node. The moment Chrome or Zoom opens the virtual camera device, the script catches the connection event and spins up your GStreamer pipeline. The second the app closes the camera, it tears the pipeline down and lets your laptop hardware sleep. [1]

### 4.1: Install the Monitoring Tool
To watch device open/close events, you need inotify-tools: [1]
bash
```sudo apt update && sudo apt install -y inotify-tools```

### 4.2: Update the Script with Debounce Logic
We will use a lockfile mechanism. When an app closes the node, the script will wait 2 seconds. If no other app opens it within those 2 seconds, it puts the hardware to sleep.
Open your script:
bash
nano ~/ipu6-ondemand.sh
Use code with caution.
Replace the entire contents with this robust, probe-aware script:

bash
```#!/bin/bash
NODE="/dev/video0"
GST_PID=""

# Clean up on exit
cleanup() {
    if [ -n "$GST_PID" ] && kill -0 "$GST_PID" 2>/dev/null; then
        kill "$GST_PID"
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "Starting IPU6 smart monitor loop..."

while true; do
    # 1. Wait for an app to open the device
    inotifywait -q -e open "$NODE" >/dev/null

    # 2. Spin up GStreamer if it isn't already running
    if [ -z "$GST_PID" ] || ! kill -0 "$GST_PID" 2>/dev/null; then
        echo "Camera target requested. Launching GStreamer..."
        gst-launch-1.0 libcamerasrc ! queue ! videoconvert ! video/x-raw,format=NV12,width=1280,height=720 ! v4l2sink device="$NODE" &
        GST_PID=$!
    fi

    # 3. Wait for a close event
    inotifywait -q -e close_nowrite -e close_write "$NODE" >/dev/null

    # 4. Debounce: Wait 2 seconds to see if Zoom/Chrome is just probing
    sleep 2

    # 5. Check if anyone reopened the device node during our sleep window
    # fuser returns non-zero if NO processes are using the node
    if ! fuser "$NODE" 2>/dev/null | grep -q -v "$GST_PID"; then
        echo "No active applications using device. Tearing down stream..."
        if [ -n "$GST_PID" ] && kill -0 "$GST_PID" 2>/dev/null; then
            kill "$GST_PID"
            wait "$GST_PID" 2>/dev/null
        fi
        GST_PID=""
    else
        echo "App probe detected or application still active. Keeping stream alive."
    fi
done
```

Save and close (Ctrl+O, Enter, Ctrl+X).

### 4.3: Install the Process Checker Dependency
The script uses fuser to reliably check if Zoom or Chrome is actively touching the webcam node. Install it via psmisc:
bash
```sudo apt update && sudo apt install -y psmisc```

### 4.4: Restart the Service
Restart your user service to load the updated loop logic:

bash
```systemctl --user restart ipu6-bridge.service```

## 5: How to Test It Now
Open Zoom or Chrome.
The initial rapid app-probing phase will safely fire up the stream, but the script will ignore the immediate close triggers.
Within 1–2 seconds, the video stream should fully populate in your app window.
When you completely close Zoom or the browser tab, the camera LED will shut down after a maximum 2-second delay.
Does the video stream now successfully initialize inside Zoom with the new debounce logic in place?

## 6: Convenience scripts

place these scripts into ~/bin:

