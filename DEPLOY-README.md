# buun-llama-cpp — Windows + CUDA 12.8 编译部署说明

本目录是 `spiritbuun/buun-llama-cpp`（llama.cpp 的实验性 fork，主打 VBR 动态 KV 量化与
TurboQuant / TCQ KV 编解码）在本机编译出的可用部署，全部产物在 `build\bin`。

## 1. 这套构建是什么

| 项目 | 值 |
|---|---|
| 源码 | `https://github.com/spiritbuun/buun-llama-cpp` |
| commit | `7dbda0c` — "cuda: harden and consolidate Q4-A32 prefill conversion" |
| 编译器 | MSVC 19.44.35222.0（VS 2022 Professional，14.44.35207） |
| CUDA | **12.8（V12.8.61）**，`C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8` |
| 目标架构 | `86-real`（RTX 3080，compute capability 8.6，VMM 可用） |
| 构建类型 | Release + Ninja，`GGML_CUDA=ON`、`GGML_CUDA_FA_QUANTS=all`、`TURBO_FA=1` |
| 产物 | `build\bin\`（约 1.0 GB，含随附的 CUDA 12.8 运行时 DLL） |

`build\bin` 里可直接运行：`llama-server.exe`、`llama-cli.exe`、`llama-completion.exe`、
`llama-bench.exe`、`llama-quantize.exe`、`llama-perplexity.exe`、`llama-imatrix.exe`、
`llama-mtmd-cli.exe`、`llama.exe`（统一入口）等。

> 现代 llama.cpp 是 DLL 结构：`llama-cli.exe` 只有 10 KB，真正的实现是
> `llama-cli-impl.dll`。**分发时必须整个 `bin` 目录一起拷**，不能只拷 exe。

## 2. 直接用

```powershell
cd E:\AID\buun-llama-cpp

# 服务（默认 VBR KV；端口 8080、上下文按参数）
.\run-server.ps1 -Model E:\LM_models\xxx.gguf -Port 8080 -Ctx 32768

# 固定档位：turbo3_tcq（3.25 bpv）
.\run-server.ps1 -Model xxx.gguf -Kv turbo3_tcq -Ctx 32768

# VBR 显式全阶梯 + 显存预算
.\run-server.ps1 -Model xxx.gguf -Kv vbr -VbrVram 8G -VbrEntry t8

# 一次性生成（注意：本 fork 的 llama-cli 不接受 -no-cnv，脚本已改用 llama-completion）
.\run-cli.ps1 -Model xxx.gguf -Prompt "hello" -Kv f16
```

`run-server.ps1` 会自动设置仓库自带的 TCQ 码本环境变量：
`TURBO_TCQ_CB=codebooks\3bit\cb_50iter_finetuned.bin`、
`TURBO_TCQ_CB2=codebooks\2bit\tcq_2bit_100iter_s99.bin`。

### KV 档位速查（`-ctk/-ctv` 或统一用 `-ct`）

- `vbr`（默认，隐式 t4 地板）：动态按显存压力逐 (层, 侧) 降级，阶梯
  `f16 → turbo8 → turbo4 → turbo3_tcq → turbo2_tcq → turbo1_tcq`。
- 固定档位：`f16`、`q8_0`、`turbo8`、`turbo4`、`turbo3`、`turbo3_tcq`、`turbo2_tcq`、`turbo1_tcq`。
- 相关开关：`--vbr-vram 8G`、`--vbr-entry t8`、`--vbr-floor t3`、`--vbr-codec auto|turbo|classic`。
- VBR / turbo 都要求 `-fa on`（脚本默认已加），且需要 `kv_unified`（server 单槽会自动打开）。

> **重要限制**：turbo / TCQ 系列的 KV block 是 128 个值，要求模型的 `n_embd_head_k`
> 是 128 的倍数。Qwen2.5-0.5B（head_dim 64）会被拒绝：
> `K cache type turbo3_tcq with block size 128 does not divide n_embd_head_k=64`。
> 用 head_dim=128 的模型（Qwen3 系、Gemma4、多数 7B+ 模型）即可。

## 3. 重新编译

```powershell
# 完整重编（会用本机默认 CUDA 12.8 + sm_86）
.\build-cuda.ps1

# 清干净重编
.\build-cuda.ps1 -Clean

# 换 CUDA / 架构 / 并行度
.\build-cuda.ps1 -CudaRoot "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8" -Arch 86 -Jobs 12

# 只配置不编译 / 只编单个目标（改代码后快速验证）
.\build-cuda.ps1 -ConfigureOnly
.\build-cuda.ps1 -Target "ggml/src/ggml-cuda/CMakeFiles/ggml-cuda.dir/int8-channel.cu.obj"
```

日志落在 `build-logs\`：`toolchain.log`（环境探测）、`configure.log`、`build.log`，
退出码写在 `configure.status` / `build.status`（0 = 成功）。
**不要靠控制台输出判断成败**，读这两个文件。

若给重编后的 `build\bin` 补 CUDA 运行时 DLL：`.\copy-cuda-dlls.ps1`。

### 本机环境注意（踩过的坑）

1. **`E:\AID\buun-llama-cpp` 的 Web UI 资源已内置**在 `tools\ui\dist\`（来自上游 release
   `llama-b11011-ui.tar.gz`）。删掉它以后重新配置时请加 `-DLLAMA_USE_PREBUILT_UI=OFF`，
   否则构建会去 HuggingFace 下载、在国内超时。
2. **CUDA 12.8 不在系统 PATH 上**（系统 PATH 只有 v13.3），所以 `cublas64_12.dll`
   (`108 MB`)、`cublasLt64_12.dll` (`660 MB`)、`cudart64_12.dll` 已被复制进 `build\bin`。
   把 `build\bin` 整个搬走即可运行，不依赖 CUDA 的 PATH。CUDA 12.x 的 DLL 在 `<CUDA>\bin`，
   **13.x 才在 `bin\x64`**，写脚本时别搞错。
3. 本机进程环境里同时存在 `Path` 和 `PATH`（还有 http_proxy/HTTP_PROXY 等大小写重名键），
   会导致 `Enter-VsDevShell` 与 `Start-Process` 直接报
   `已添加项。字典中的关键字:"Path"所添加的关键字:"PATH"`。
   所以 `build-cuda.ps1 -Toolchain auto` 会自动回退到 **manual 模式**：
   手工拼 `PATH/INCLUDE/LIB` + `CUDAHOSTCXX`，并用显式
   `-DCMAKE_C_COMPILER/-DCMAKE_CXX_COMPILER/-DCMAKE_CUDA_COMPILER/-DCMAKE_CUDA_HOST_COMPILER`。
   这是本机唯一稳定的路径（`cmd.exe` 也被工具层拦截，走不了 vcvars64.bat）。
4. 反复构建时注意：**后台任务别设 timeout**，否则 ninja 会在半路被连带杀掉。

## 4. 为 MSVC 做的两处源码补丁（必需）

代码都在 `ggml\src\ggml-cuda\bsa_vendor\`（fork 自带的 vendored CUTLASS）：

**补丁 1 — `cutlass/gemm/kernel/gemm_universal.hpp`**
把 7 个 Hopper（SM90）kernel 头文件的 include 包进
`#if !defined(CUTLASS_DISABLE_SM90_KERNELS)`。

原因：只要 CUDA ≥ 12，`CUTLASS_ARCH_MMA_SM90_SUPPORTED` 恒为真，
`sm90_gemm_tma_warpspecialized_pingpong.hpp` 就会被**无条件解析**，
而 MSVC 19.44 解析不了它（`C4346` + `C2061`，定位在 `OrderedSequenceBarrier::SharedStorage`）。
这些 SM90 内核只有编 sm_90a 时才用得上：`int8-channel.cu` 走的是
`cutlass_scaled_i8_sm80`（`cutlass::arch::Sm80`）。因此 sm_86 构建传
`-DCUTLASS_DISABLE_SM90_KERNELS` 跳过它们，功能无损。

**补丁 2 — 编译标志 `-Xcompiler /Zc:__cplusplus`**

原因：MSVC 即使给了 `-std=c++17`，`__cplusplus` 仍是 `199711L`。
vendored CUTLASS 依据 `__cplusplus` 决定是否给 `const_min/const_max` 加 `constexpr`，
于是 MSVC 报一片
`cutlass/epilogue/threadblock/output_tile_thread_map.h(242): error: expression must have a constant value`。
加 `/Zc:__cplusplus` 后这批错误全部消失（`-Xcompiler` 保证 nvcc 不直接看到它）。

两个补丁都由 `build-cuda.ps1` 自动带上：架构 < 90 时加 `-DCUTLASS_DISABLE_SM90_KERNELS`，
`-DCMAKE_CUDA_FLAGS` 里始终带 `-Xcompiler /Zc:__cplusplus`。
补丁 2 是**纯编译选项**，改回源码树不影响；补丁 1 改了 vendored 头文件，
`git diff ggml/src/ggml-cuda/bsa_vendor/` 可查看。

## 5. 验证结果（2026-09-17 本机实测）

```
version: 0.4.1-dev (build 1, commit 7dbda0c)
built with MSVC 19.44.35222.0 for Windows AMD64

ggml_cuda_init: found 1 CUDA devices (Total VRAM: 20479 MiB):
  Device 0: NVIDIA GeForce RTX 3080, compute capability 8.6, VMM: yes, VRAM: 20479 MiB
Available devices:
  CUDA0: NVIDIA GeForce RTX 3080 (20479 MiB, 19297 MiB free)

system_info: n_threads = 8 / 16 | CUDA : ARCHS = 860 | USE_GRAPHS = 1 | FA_QUANTS = all | TURBO_FA = 1
```

- Web UI 已内嵌：`GET /` → 200；`GET /_app/immutable/bundle.*.js` → 200（需 `Accept-Encoding: gzip`）。
- `GET /health` → `{"status":"ok"}`；`GET /v1/models` → 200。
- `POST /v1/chat/completions`（Qwen2.5-0.5B Q4_K_M，f16 KV）→
  `predicted_per_second = 289.9`，`prompt_per_second = 194.7`（GPU 生效）。
- VBR 控制器与 turbo 码本选择正常：
  `VBR dynamic turbo runtime controller: KV budget auto, entry tier f16, floor 1.25 bits/value`。
- TCQ 编解码在 GPU 上启用：
  `TCQ encode: using shared-memory backtrace (8192 bytes/block)`、
  `TCQ decode: context-adaptive V alpha enabled`。

## 6. 已知限制

- **未编入 SM90（Hopper）内核**（见补丁 1）。本构建面向 sm_86；如需 sm_90a 请去掉
  `-DCUTLASS_DISABLE_SM90_KERNELS` 并改用在能解析这些头文件的工具链（Linux + GCC）。
- `LLAMA_CURL` 选项在源码里已废弃（传了会被忽略）；`-hf` 自动下载模型的行为取决于
  构建时的 curl 探测结果。
- 本构建 `-DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF`，所以 `bin` 里没有测试程序。
- 该 fork 的实验性很强（README 自称 experimental R&D），出问题先看 `-v` 日志里的
  VBR degrade 行（`Grep "Final estimate"` / `tg64` 是它自己的提示）。

## 7. 目录里新增的文件

| 文件 | 用途 |
|---|---|
| `build-cuda.ps1` | 配置 + 编译，`-Clean/-ConfigureOnly/-Target/-Toolchain/-ExtraCudaFlags` |
| `run-server.ps1` | 启动 llama-server（含 KV 档位、VBR 参数、TCQ 码本） |
| `run-cli.ps1` | 一次性生成（驱动 `llama-completion.exe`） |
| `copy-cuda-dlls.ps1` | 用 dumpbin 解析真实导入表，把 CUDA 运行时 DLL 补进 `build\bin` |
| `build-logs\probe\nvcc-probe.sh` | 单 TU 快速编译探针（手工 MSVC 环境，约 1 分钟/次） |
| `build-logs\probe\t1.cu` | 复现 MSVC 解析 CUTLASS 失败的 12 行用例 |
| `tools\ui\dist\` | 内嵌 Web UI 的预构建资源（未跟踪，已加入 `.git/info/exclude`） |
