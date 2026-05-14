---
name: ros1_bridge 從 osrf 預建 image 換成自建
description: app/ros1_bridge 放棄 osrf/ros:foxy-ros1-bridge 改用 ros:foxy-ros-base-focal 自建 — Jetson 相容性需求
type: project
originSessionId: ac27ac04-4fee-4b6f-a370-98120e06c59d
---
`app/ros1_bridge` 的 devel stage 從 `osrf/ros:foxy-ros1-bridge`（x86_64 only）改成
`ros:foxy-ros-base-focal`（multi-arch，含 arm64），再透過 snapshot apt repo 自己裝
`ros-noetic-ros-comm` + `ros-foxy-ros1-bridge`。

**Why:** `osrf/ros:foxy-ros1-bridge` 沒有 arm64 manifest，無法在 Jetson 上 pull/run。
改用官方 `ros:foxy-ros-base-focal` 後可以同時支援 amd64 與 arm64，等同於自建
`docker_images_ros2/ros1_bridge/create_ros_ros1_bridge_image.Dockerfile.em` 的產物。

**How to apply:** 之後看到 ros1_bridge 相關 issue 時，先確認 base image 是 `ros:foxy-ros-base-focal`
而非 osrf。若有人問「為什麼不直接用 osrf 預建 image？」→ Jetson 限制。
Foxy 已 EOL，snapshot repo (`snapshots.ros.org/noetic/final`) 是長期保存 apt 來源。
