import os
from glob import glob

from setuptools import setup

package_name = "ros_launchers"

setup(
    name=package_name,
    version="0.0.0",
    packages=[package_name],
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        (os.path.join("share", package_name, "launch"), glob("launch/*.py")),
        (os.path.join("share", package_name, "config"), glob("config/*.yaml")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Matej Boxan",
    maintainer_email="matej.boxan@norlab.ulaval.ca",
    description="FoMo bench example ROS2 launchers",
    license="BSD3",
    tests_require=["pytest"],
    entry_points={},
)
