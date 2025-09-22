ARG BASE_IMAGE=arm64v8/ros:humble
FROM ${BASE_IMAGE}

# Fix for Hash Sum mismatch error
# from this link https://stackoverflow.com/questions/67732260/how-to-fix-hash-sum-mismatch-in-docker-on-mac
RUN echo "Acquire::http::Pipeline-Depth 0;" > /etc/apt/apt.conf.d/99custom && \
    echo "Acquire::http::No-Cache true;" >> /etc/apt/apt.conf.d/99custom && \
    echo "Acquire::BrokenProxy    true;" >> /etc/apt/apt.conf.d/99custom

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    ros-humble-rosbag2-storage-mcap \
    ros-humble-foxglove-bridge \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install numpy==1.24.4 scipy==1.10.1 matplotlib==3.4.2 evo

# Set up a standard working directory
WORKDIR /app

# Copy the entire src directory into the WORKDIR
# This preserves the structure (e.g., /app/entrypoints, /app/scripts)
COPY src/ .

# Ensure all entrypoints are executable with a single command
RUN chmod +x entrypoints/*.sh

# Install Navtech message definitions to play them with ros2 bag play
RUN mkdir -p /tmp/build_ws/src
RUN git clone https://bitbucket.org/norlab/navtech_driver.git /navtech_driver \
    && mv /navtech_driver/ros/ros2/src/navtech_msgs /tmp/build_ws/src/navtech_msgs \
    && rm -rf /navtech_driver \
    && cd /tmp/build_ws \
    && . /opt/ros/humble/setup.sh \
    && colcon build --install-base /opt/ros/humble --merge-install \
    && rm -rf /tmp/build_ws

# Set our new script as the default entrypoint for the image
ENTRYPOINT ["/app/entrypoints/entrypoint_ros.sh"]
