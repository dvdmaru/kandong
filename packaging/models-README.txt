把模型放這裡
============

看懂需要「翻譯模型」才能翻字幕；看沒有字幕的影片，另外需要「語音辨識模型」。
兩種拿法擇一：

A. 一鍵下載（最簡單）
   Windows：雙擊 KanDong 資料夾裡的「一鍵下載模型」
   Mac    ：雙擊 KanDong 資料夾裡的「一鍵下載模型.command」
   會從 Hugging Face 官方下載、自動放進這個資料夾，並檢查檔案是否完整。

B. 自己下載（想先確認來源、或用自己的下載工具）
   用瀏覽器打開下面的連結下載，下載好的檔案「直接放進這個 models 資料夾，檔名不要改」。

   翻譯模型・標準（約 4.6GB，翻得比較好，建議記憶體 16GB 以上）
     檔名：Hy-MT2-7B-Q4_K_M.gguf
     下載：https://huggingface.co/tencent/Hy-MT2-7B-GGUF/resolve/main/Hy-MT2-7B-Q4_K_M.gguf
     SHA256：9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b

   翻譯模型・輕量（約 1.1GB，快很多；記憶體 8GB 或電腦較舊選這個）
     檔名：Hy-MT2-1.8B-Q4_K_M.gguf
     下載：https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/main/Hy-MT2-1.8B-Q4_K_M.gguf
     SHA256：dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699

   語音辨識模型（約 574MB，只有看「沒字幕的影片」才需要）
     檔名：ggml-large-v3-turbo-q5_0.bin
     下載：https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
     SHA256：394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2

   翻譯模型兩個都放的話，記憶體 12GB 以上會自動用標準版，否則用輕量版。

模型授權：Hy-MT2 為騰訊以 Apache-2.0 釋出；Whisper 模型為 OpenAI 以 MIT 釋出。
