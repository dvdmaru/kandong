# 第三方元件與授權

看懂 KanDong 自己的程式（`scripts/`、`ui/` 的設定、`server/`、`mac/`、`packaging/`）是 MIT 授權，見 `LICENSE`。
下載包裡另外附了下列第三方元件，各自依其授權散布；授權全文在下載包的 `licenses/` 資料夾（原始碼庫的 `packaging/licenses/`）。

| 元件 | 用途 | 版本 | 授權 | 原始碼 |
|---|---|---|---|---|
| mpv | 播放器本體（Windows 包內附） | v0.41.0-918-g1d1568614（zhongfly/mpv-winbuild 的 x86_64 build） | GPL-2.0-or-later（此 build 含 GPL 元件） | https://github.com/mpv-player/mpv ，build 腳本 https://github.com/zhongfly/mpv-winbuild |
| FFmpeg | 抽內嵌字幕軌、切語音辨識用的音訊（Windows 包內附） | N-125907-ga7e72069f1-20260802（BtbN/FFmpeg-Builds win64-gpl） | GPL-3.0-or-later（`--enable-gpl --enable-version3`） | https://github.com/FFmpeg/FFmpeg ，build 腳本 https://github.com/BtbN/FFmpeg-Builds |
| Vulkan Runtime（vulkan-1.dll） | 上面這個 mpv build 需要（Windows 包內附） | LunarG Vulkan Runtime x64 | MIT／Apache-2.0 等開源授權（見 VulkanRT-License.txt） | https://vulkan.lunarg.com/ |
| uosc | 控制列、右鍵選單等介面（兩個包都內附） | 5.13.0 | LGPL-2.1 | https://github.com/tomasklaen/uosc |
| Hy-MT2 翻譯模型 | 翻譯（不內附；一鍵下載或手動下載） | Hy-MT2-7B／1.8B GGUF Q4_K_M | Apache-2.0 | https://huggingface.co/tencent/Hy-MT2-7B-GGUF |
| llama.cpp（llama-server） | 翻譯引擎（Windows 包內附；Mac 用 Homebrew 安裝） | b10204（win-vulkan-x64） | MIT | https://github.com/ggml-org/llama.cpp |
| whisper.cpp（whisper-server） | 語音辨識引擎（Windows 包內附；Mac 用 Homebrew 安裝） | b5454（whisper-bin-x64） | MIT | https://github.com/ggml-org/whisper.cpp |
| Whisper large-v3-turbo 模型 | 語音辨識（不內附；一鍵下載或手動下載） | ggml q5_0 | MIT | https://huggingface.co/ggerganov/whisper.cpp |

## 對 uosc 的修改

只有一處：安裝時（`ui/install-uosc.sh`）刪掉 `scripts/uosc/main.lua` 裡字幕選單的 `download_command` 那一行，
拿掉「線上搜尋字幕」按鈕——看懂不下載字幕。其餘檔案與上游 5.13.0 release 相同（安裝前驗 SHA256）。

## GPL 元件的原始碼

mpv 與 FFmpeg 的對應原始碼可從上表的上游與 build 腳本取得（版本字串含 git commit）。
若需要我們提供與下載包內執行檔完全對應的原始碼，請在 GitHub 開 issue，我們會提供。
