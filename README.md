# fomo-bench

## Installation
fomo-bench is a docker-based evaluation platform for proprioceptive, lidar, radar and visual odometry, localization and SLAM algorithms.
It is capable of evaluating one or multiple algos simultaneously.
To start, copy the example `.env` file:
```shell
cp .env.example .env
```
and edit it.

The evaluation actively monitors every running docker container for CPU/memory and other stats.
These stats are saved as `.json` files in the `$OUTPUT_PATH_HOST` directory.
If `matplotlib` is installed, the script also produces simple visualization of the statistics.
```shell
python3 -m venv .venv
source .venv/bin/activate
pip install matplotlib
```
The `.venv` directory is detected automatically.

## Running the evaluation
TODO

## Preparing your docker image
TODO

## Data export
If your solution requires additional time to complete after the ros2 bag play finishes, for example to save the output map, you can extend the sigterm and sigkill timeouts for your ros2 node:
  ```
  my_node = Node(
      sigterm_timeout="30",  # Wait 30 seconds before escalating to SIGTERM
      sigkill_timeout="5",  # Wait 5 more seconds before SIGKILL
      ...
      )
  ```
The evaluation pipeline is running ROS2 humble. Due to some [limitations](https://github.com/ros2/launch/issues/666) of this system, in order for your prepared docker image to exit correctly, please follow these:

- Use `STOPSIGNAL SIGINT` in your Dockerfile.
- Use the `--noninteractive` flag in your ros2 launch/run command, e.g.:
  ```
  ros2 launch --noninteractive my_package my_launch.py
  ```

To trigger on the sigterm signal, you can include a shutdown callback in your ROS2 code. For example:
```C++
int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);


    auto node = std::make_shared<MyNode>();

    // Register shutdown callback on the global context
    auto context = rclcpp::contexts::get_global_default_context();

    // Use a weak pointer to avoid keeping the node alive
    std::weak_ptr<MyNode> weak_node = node;

    context->add_on_shutdown_callback(
        [weak_node]() {
            if (auto n = weak_node.lock()) {
                std::cout << "[mapper_node] Received a shut down call" << std::endl;
                n->saveMapOnShutdown();
                std::cout << "[mapper_node] Shutdown save completed" << std::endl;
            }
        });

    try {
        rclcpp::spin(node);
    } catch (const std::exception & e) {
        std::cout << "Exception: " << e.what();
    }

    rclcpp::shutdown();
    return 0;
}
```


## Published topics
Your solution must publish on `/estimated_odom`, `/estimated_pose` or `/estimated_pose_covariance` topics.
Alternatively, if your solution performs optimization of the previously estimated poses, e.g. through graph optimization, you can also save the final estimated trajectory to a file. This file must follow the [tum](https://cvg.cit.tum.de/data/datasets/rgbd-dataset/file_formats) format and be saved to: `$STORAGE_PATH/trajectory.txt`.
