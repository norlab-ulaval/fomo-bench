# SLAM Pipeline and Evaluation Framework

[](https://opensource.org/licenses/MIT)

This repository provides a robust and automated framework for running, benchmarking, and evaluating containerized SLAM (Simultaneous Localization and Mapping) systems. It is designed for streamlined use in robotics competitions and research, leveraging Docker and Docker Compose for portability and reproducibility.

### Features

  * **Automated Pipeline:** Execute the entire workflow—running SLAM, playing data, and evaluating results—with a single command.
  * **Containerized & Reproducible:** Runs any Docker-based SLAM system, ensuring consistent environments.
  * **Flexible Configuration:** Easily configure dataset paths, playback parameters, and the target SLAM image via a central `.env` file.
  * **Modular Structure:** Cleanly organized source code, entrypoints, and configuration make the framework easy to understand and extend.

### 🏆 Used In

This framework is the official evaluation tool for the following robotics competitions:

  * **SLAM Challenge Series @ CTU in Prague:** [comrob-ds.fel.cvut.cz:555](https://comrob-ds.fel.cvut.cz:555/?page=1)

-----

## Table of Contents

- [SLAM Pipeline and Evaluation Framework](#slam-pipeline-and-evaluation-framework)
    - [Features](#features)
    - [🏆 Used In](#-used-in)
  - [Table of Contents](#table-of-contents)
  - [📦 Prerequisites](#-prerequisites)
  - [🚀 Quick Setup](#-quick-setup)
  - [🎯 Usage Scenarios](#-usage-scenarios)
    - [👨‍💻 For Competition Participants](#-for-competition-participants)
      - [**Step-by-Step Example: Building and Testing a Local SLAM Image**](#step-by-step-example-building-and-testing-a-local-slam-image)
      - [**Preparing Your Own SLAM System**](#preparing-your-own-slam-system)
    - [큐 For Dataset Curators](#큐-for-dataset-curators)
  - [📁 Example Dataset](#-example-dataset)
  - [⚙️ Advanced Usage \& Details](#️-advanced-usage--details)
    - [Manual Control](#manual-control)
    - [Visualization with RViz](#visualization-with-rviz)
    - [Development Workflow (for this Repository)](#development-workflow-for-this-repository)
  - [🛠 Troubleshooting](#-troubleshooting)
  - [📜 License](#-license)

-----

## 📦 Prerequisites

Ensure you have the following software installed on your system:

  * [Docker Engine](https://docs.docker.com/get-docker/)
  * [Docker Compose](https://docs.docker.com/compose/install/)

-----

## 🚀 Quick Setup

This guide covers the initial setup of the framework. For specific use cases, please see the **Usage Scenarios** below.

1.  **Clone the Repository:**

    ```bash
    git clone https://github.com/comrob/slam-bench.git slam_competition
    cd slam_competition
    ```

2.  **Create Environment File:**
    Copy the example environment file. You will configure this file based on your chosen scenario.

    ```bash
    cp .env.example .env
    ```

-----

## 🎯 Usage Scenarios

This framework is designed for two primary user groups. Please follow the guide that matches your goal.

### 👨‍💻 For Competition Participants

**Goal:** To containerize your SLAM system and test it locally, simulating the exact process used by the official evaluation platform.

**Recommendation:** This guide walks you through building a provided example (`VINS-Mono-crl`) from source and running it with this framework. Following these steps is the best way to understand how to prepare your own SLAM system for the competition.

#### **Step-by-Step Example: Building and Testing a Local SLAM Image**

1.  **Clone the Example SLAM System:**
    First, get the source code for `VINS-Mono-crl`, which serves as a template for a dockerized SLAM solution.

    ```bash
    git clone https://github.com/comrob/VINS-Mono-crl.git
    ```

2.  **Build the SLAM Docker Image Locally:**
    Navigate into the cloned repository and build the Docker image. This process simulates you building your own SLAM system's image.

    ```bash
    cd VINS-Mono-crl/docker
    make # vins-mono-crl:latest will be build
    cd ..
    ```

    You now have a local Docker image named `vins-mono-crl:latest` ready for testing.

3.  **Set up the Evaluation Framework & Dataset:**
    If you haven't already, complete the [Quick Setup](#quick-setup) for this `slam-bench` repository and download the `shellby-0225-train-lab` dataset from the [Example Dataset](#-example-dataset) link.

4.  **Configure the `.env` File:**
    In the `slam_competition` directory, open your `.env` file and point it to your locally built image and the downloaded dataset.

    ```dotenv
    # Absolute path to the dataset directory
    BAGFILES_PATH_HOST=/home/user/datasets/shellby-0225-train-lab

    # Name of your locally built Docker image
    SLAM_IMAGE=vins-mono-crl:latest
    ```

    > **Note:** Replace `/home/user/` with the actual path on your system.

5.  **Run the Full Pipeline:**

    ```bash
    ./run_pipeline.sh
    ```

    This will use your locally built `vins-mono-crl:latest` image to run the evaluation. This mirrors the exact process you'll follow for your own algorithm.

#### **Preparing Your Own SLAM System**

After running the example, you are ready to adapt the process for your own solution. Keep the following in mind:

  * **ROS1 is Straightforward:** If your solution already runs in ROS1, the containerization process is very direct. You primarily need to create a `Dockerfile` that builds your workspace and runs your launch file.
  * **Dockerfile Best Practices:** Your `Dockerfile` should be clean and minimal. We highly recommend studying the [VINS-Mono-crl Dockerfile](https://github.com/comrob/VINS-Mono-crl/blob/master/docker/Dockerfile) as a template. It should:
    1.  Install only the necessary dependencies.
    2.  Build a minimal ROS workspace.
    3.  Use `CMD` or `ENTRYPOINT` to execute the `roslaunch` command that starts your SLAM node. Ensure the topics in your launch file match the topics provided in the competition datasets.

<details>
<summary><strong>Click to expand: Competition Submission Format</strong></summary>

To submit your solution, package your Docker image and an optional description file.

1.  **Save your Docker Image:** Archive your final SLAM image into a `.tar` file.

    ```bash
    # Using docker save
    docker save -o my-slam-image.tar your-slam-image:your-tag

    # Or using the repository script
    ./docker/docker2tar.sh your-slam-image:your-tag
    ```

2.  **(Optional) Create a `description.yaml`:** This file specifies runtime parameters. **Check the official competition rules for the required fields.**

    ```yaml
    # Example description.yaml
    ROSBAG_PLAY_RATE: 5.0
    ```

    **Available Parameters:**

      * `ROSBAG_PLAY_RATE`: (Optional, default: 5.0) Controls `rosbag play` speed.

3.  **Create the ZIP Archive:** Create a `.zip` file containing the `.tar` image and the optional `.yaml` file.

    ```bash
    zip submission.zip my-slam-image.tar description.yaml
    ```

    This `submission.zip` file is ready for upload.

</details>

### 큐 For Dataset Curators

**Goal:** To prepare and validate a new dataset for use in a competition.

**Recommendation:** To ensure your dataset is compatible with the evaluation platform, you should test it with this framework using a known, working SLAM algorithm.

1.  **Structure Your Dataset:** Organize your dataset files into the required directory structure. See the **[Example Dataset](#-example-dataset)** section below for the correct layout (`sensors`, `reference`, `calibration`, etc.).

2.  **Test Locally:** Configure the `.env` file to point `BAGFILES_PATH_HOST` to your new dataset's location. Use a reliable, locally built SLAM image (like `vins-mono-crl:latest` from the example above) for `SLAM_IMAGE` to run the pipeline.

    ```bash
    ./run_pipeline.sh
    ```

    If the pipeline completes successfully and generates a sensible evaluation report, your dataset is correctly structured.

3.  **Contact Organizers:** Once you have validated your dataset, contact the competition organizers to arrange for it to be uploaded to the official evaluation server.

-----

## 📁 Example Dataset

We provide a sample collection of datasets to help you get started.

<a href="https://drive.google.com/drive/folders/1ef0k0JzQpKvGQkLGCsqh9FhuewvpQVYq">
https://drive.google.com/drive/folders/1ef0k0JzQpKvGQkLGCsqh9FhuewvpQVYq
</a>

To test the framework with your own custom dataset, it **must** follow the same directory structure, including providing sensor calibration files:

```
<your_dataset_root>/      # e.g., /home/user/datasets/my_awesome_dataset
├── sensors/
│   └── *.bag             # One or more .bag files containing sensory data
├── reference/
│   └── reference.txt     # The ground truth trajectory file
└── calibration/
    ├── intrinsics.yaml   # Intrinsic parameters for cameras, etc.
    └── extrinsics.yaml   # Extrinsic transformations between sensor frames
```

-----

## ⚙️ Advanced Usage & Details

<details>
<summary><strong>Click to expand: Configuration (`.env`) Details</strong></summary>

All pipeline parameters are controlled from the `.env` file. Below is a description of the key variables.

| Variable | Description | Example Value |
| :--- | :--- | :--- |
| `BAGFILES_PATH_HOST` | **Absolute path** to the specific dataset directory you want to run. | `$HOME/datasets/shellby-0225-train-lab` |
| `BAGFILE_NAME` | The name of the `.bag` file or a subdirectory within `BAGFILES_PATH_HOST` that contains the bag file(s). Recommended to use `sensors`. | `sensors` |
| `SLAM_IMAGE` | The Docker image for the SLAM system you want to evaluate. | `my-slam-algo:latest` |
| `CRL_SLAM_IMAGE` | A fallback SLAM image if `SLAM_IMAGE` is not set. | `ghcr.io/comrob/liorf-crl:latest` |
| `REFERENCE_TRAJECTORY_FILE_HOST` | **Absolute path** to the ground truth trajectory file. The default value is usually sufficient. | `$BAGFILES_PATH_HOST/reference/reference.txt` |
| `ROSBAG_PLAY_RATE` | Playback rate for the `rosbag play` command. | `5.0` |
| `TOPICS_FILE` | (Optional) Path relative to `BAGFILES_PATH_HOST` to a file listing ROS topics to play. | `tracks/passive.txt` |
| `DEV_DOCKER` | Set to `true` to use the locally built `slam-bench:latest` image. **For developing this framework, not the SLAM system.** | `true` |
| `SLAM_CONFIG_OVERRIDE_FILE` | (Optional) Host-side path to a config file mounted into the SLAM container at `/config/override.yaml`. | `./config/slam/override.yaml` |

</details>

<details>
<summary><strong>Click to expand: Framework Workflows (Manual Control, Visualization, etc.)</strong></summary>

### Manual Control

You can run individual components of the pipeline for fine-grained control and debugging.

1.  **Start Background Services:** Launch your SLAM system and the odometry recorder in detached mode (`-d`).
    ```bash
    docker compose up -d run_slam record_odometry
    ```
2.  **Play the Dataset:** Run the `play_bag` service in the foreground.
    ```bash
    docker compose up play_bag
    ```
3.  **Evaluate the Trajectory:** After playback finishes, run the evaluation service.
    ```bash
    docker compose up evaluate_trajectory
    ```
4.  **Clean Up:** Stop and remove all pipeline containers.
    ```bash
    docker compose down
    ```

### Visualization with RViz

To view SLAM outputs on your host machine:

1.  Allow local connections to your X server (run once per session):
    ```bash
    xhost +
    ```
2.  Ensure the `DISPLAY` environment variable is correctly set in your shell.
3.  Run the pipeline. The SLAM container will connect to your host's display.

### Development Workflow (for this Repository)

To test changes made to this evaluation framework itself:

1.  Modify the code in the `src/` directory.
2.  Build the local Docker image:
    ```bash
    ./docker/build.sh
    ```
3.  Set `DEV_DOCKER=true` in your `.env` file.
4.  Run the pipeline to test your changes:
    ```bash
    ./run_pipeline.sh
    ```

</details>

-----

## 🛠 Troubleshooting

<details>
<summary><strong>Click to expand: Common Issues and Solutions</strong></summary>

  * **Evaluation fails or the score is zero:**

      * Check logs: `docker compose logs record_odometry`. Is it receiving messages?
      * Verify your SLAM container is publishing the trajectory correctly.
      * Ensure `$OUTPUT_PATH_HOST/estimated_trajectory.txt` is created and not empty.

  * **Local code changes (to this framework) have no effect:**

      * Did you run `./docker/build.sh` after making changes?
      * Is `DEV_DOCKER=true` set in your `.env` file?

  * **RViz is not displaying anything:**

      * Did you run `xhost +` on your host machine *before* starting the pipeline?
      * Is your `DISPLAY` environment variable correctly set?

</details>

-----

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.