# buun-llama-cpp —— Windows · CUDA 12.8 · sm_86 预编译版

预编译的 Windows 64 位二进制，基于 [spiritbuun/buun-llama-cpp](https://github.com/spiritbuun/buun-llama-cpp) @ `7dbda0c` 编译，工具链 MSVC 19.44 + CUDA 12.8。

> 本发布仅包含可执行文件与运行库，不包含任何模型权重（`.gguf` 需另行下载）。

## 硬件兼容性（重要）

本构建**只编译了 NVIDIA 计算能力 8.6（Ampere）的机器码，未内嵌 PTX**，因此：

| 支持 | 不支持 |
|---|---|
| RTX 3060 / 3060 Ti | RTX 40 系（sm_89 / Ada） |
| RTX 3070 / 3070 Ti | RTX 50 系（sm_120 / Blackwell） |
| RTX 3080 / 3080 Ti | RTX 20 系（sm_75 / Turing） |
| RTX 3090 / 3090 Ti | A100（sm_80）/ H100（sm_90） |
| RTX A2000 – A6000 | AMD / Intel / Apple 显卡 |
| A10 / A40 / A2 / A30 | Linux / macOS / ARM |

即：**仅 NVIDIA compute capability 8.6 的显卡可运行**。RTX 40/50 系等多半跑不了。

## 运行环境要求（使用前请先装好）

1. **操作系统**：Windows 10 / 11，64 位。
2. **NVIDIA 显卡驱动 ≥ 572.x**（CUDA 12.8 的最低要求，2025 年后的 Game Ready / Studio 驱动即可；更新版本向后兼容）。
3. **Microsoft Visual C++ 2022 Redistributable (x64)** —— 二进制动态链接了 `VCRUNTIME140.dll`，未静态打进 exe。
4. **无需安装 CUDA Toolkit** —— `build\bin` 内已附带 `cublas64_12.dll` / `cublasLt64_12.dll` / `cudart64_12.dll`，同目录优先加载，自包含。

## 快速开始

```powershell
# 解压后进入 build\bin 目录
cd build\bin
# 启动 OpenAI 兼容服务（默认端口 8080）
.\llama-server.exe -m <你的模型>.gguf -ngl 99
```

Web UI 已内嵌，浏览器打开 `http://localhost:8080` 即可对话。

## 该 fork 的注意事项

- **Turbo / TCQ 的 KV block 大小为 128**，要求模型的 `n_embd_head_k % 128 == 0`（即 head_dim 为 128 的倍数）。不满足的模型（如 Qwen2.5-0.5B，head_dim=64）会被拒绝走 turbo 路径；请选用 head_dim 128 倍数的模型。
- 多卡 NCCL 已编入，仅多 GPU 时生效；单卡无影响。

## 校验

- 版本：`0.4.1-dev (build 1, commit 7dbda0c)`，MSVC 19.44.35222.0，Windows AMD64。
- 启动信息应显示：`CUDA : ARCHS = 860 | USE_GRAPHS = 1 | FA_QUANTS = all | TURBO_FA = 1`。

## 许可

本仓库为 llama.cpp 衍生项目的预编译产物，包含上游及 vendored 组件（如 CUTLASS）的代码。
发布前请确认并随附相应的许可证（llama.cpp MIT、CUTLASS MIT 及本 fork 的许可条款）。
