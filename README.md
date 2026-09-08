# Zero Type

> 一個 Vibe Coding 出來的繁體中文語音輸入工具。

市面上大多數語音辨識軟體對繁體中文（特別是台灣人慣用的晶晶體中英混用語境）支援度有限，且背後處理邏輯不透明。ZeroType 透過直接串接外部 LLM API，打造一套開放、透明、可自訂的語音辨識輸入系統。

**你只需要自備 API Key，其餘一切開源。**

---

## ✨ 功能特色

### 🎙️ 全局快捷鍵錄音
- 自訂全局快捷鍵（預設 `⌥ Option + Space`），在任何應用程式中觸發錄音
- 錄音中顯示浮動音波 Overlay，提供即時視覺回饋
- 按下 `Esc` 或點擊取消按鈕可中止錄音

### 🧠 AI 驅動的語音辨識
- 支援 **OpenAI**（`gpt-4o-transcribe`）與 **Google Gemini**（`gemini-*`）兩大語音辨識後端
- 辨識完成後，結果自動貼至游標所在位置（模擬 `⌘V`）
- 支援自訂 API Endpoint（可使用 OpenAI-compatible 的第三方服務）

### 🇹🇼 針對繁體中文深度優化的提示詞
內建的轉錄提示詞針對台灣使用情境做了以下優化：

| 功能 | 說明 |
|------|------|
| **晶晶體支援** | 中英文混用語句自然處理，英文單字保留原文不翻譯、不中文化 |
| **智慧過濾廢詞** | 自動剔除「嗯」、「啊」、「呃」、「喔」、「那個」、「然後」、「基本上」等停頓填充詞 |
| **口誤修正偵測** | 偵測到「不對」、「應該是」、「我說錯了」、「才對」等字眼，自動捨棄前段錯誤並保留修正內容 |
| **智慧標點** | 根據語意自動補上逗號、句號，不需手動停頓 |
| **自動條列輸出** | 偵測到序數（第一、第二）或連接詞（首先、然後、最後）時，自動轉為 `1. 2. 3.` 或 `- ` 格式並換行 |
| **格式口語還原** | 說出「大寫」、「小寫」、「空格」、「底線」、「驚嘆號」等，自動還原為對應字元 |
| **空白錄音保護** | 錄音檔為空時直接返回空字串，嚴禁自行幻想內容 |

### 📖 自訂字典
- 可設定個人化的專有名詞字典（人名、品牌、術語）
- 辨識時優先採用字典用字，確保拼寫正確

### ⚙️ 設定頁面
- 深色 / 淺色模式切換
- 開機自動啟動
- 快捷鍵自訂（支援任意組合鍵）
- 麥克風權限與輔助使用權限狀態即時顯示

---

## 🔧 使用前準備

### 系統需求
- macOS 11.0+
- Flutter 3.x（如需自行 build）

### 必要系統授權
1. **麥克風** — 錄音所需
2. **輔助使用（Accessibility）** — 模擬鍵盤輸入（`⌘V` 貼上）所需

### API Key
前往以下任一服務申請 API Key：
- [OpenAI](https://platform.openai.com/api-keys)（支援 Transcribe 語音辨識）
- [Google AI Studio](https://aistudio.google.com/app/apikey)（支援 Gemini 多模態）

---

## 🚀 快速開始

### 方法一：直接下載（推薦）

1. 前往 [Releases](https://github.com/your-username/zerotype/releases) 頁面下載最新的 `.dmg`
2. 開啟 `.dmg` 並將 **ZeroType.app** 拖入 Applications 資料夾
3. 首次執行時，依照提示授予以下權限：
   - **麥克風** — 語音輸入所需
   - **輔助使用（Accessibility）** — 模擬鍵盤貼上所需
4. 在 App 內的「模型設定」填入你的 API Key，即可開始使用

### 方法二：從原始碼 Build（進階）

```bash
git clone https://github.com/your-username/zerotype.git
cd zerotype
flutter pub get
flutter run -d macos
```

---

## 🌍 語言支援 & 貢獻 (Localization & Contribution)

- **地區限制**：目前此 App 主要針對 **台灣使用情境** 設計，輸出內容以 **繁體中文** 與 **英文** 為主。未來是否有增加其他語言支援？若「有緣」的話之後再行考慮。
- **回報問題與協助**：如果你在使用上發現任何問題，或是單純想提供改進建議，歡迎直接發 **Issue** 或發 **Pull Request** 給我。只要我有看到訊息，第一時間就會來幫大家處理與解決。

---

## 📜 版本更新紀錄 (Release Notes)

### [v1.0.2] - 當前版本
- **新增歷史紀錄頁** 🎨
  - 提供歷史產生逐字稿的紀錄語音檔，並可提供檢視。
  - 新增總轉寫次數與總花費（USD）的持久化累計統計。
- **最長錄音自訂** ⏱️
  - 設定中新增「最長錄音時間」選項，範圍 1-5 分鐘，預設為 1 分鐘。
- **編輯器優化** ✍️
  - 提示詞編輯框寬度與高度現在會隨視窗大小自適應，不再固定長度。

### [v1.0.1]
- **錄音音效支援** 🔊 — 可設定錄音開始與結束提示音。
- **功能修復** 🐛 — 修正 macOS 上視窗關閉後無法再次開啟的問題。
- **提示詞優化** 📝 — 進一步精簡轉錄用的系統 Prompt。

---

## 📝 License

MIT — 自由使用、修改、散布，唯需自備 API Key。


## Security hardening in this fork

API keys now use the OS secure vault. Existing transcripts and history recordings migrate to authenticated encryption on first access. Custom endpoints require HTTPS; authenticated redirects are disabled. Cancellation aborts requests and prevents late results from being saved or pasted. History playback no longer invokes PowerShell. Retention runs periodically while the app is open.

See [SECURITY.md](SECURITY.md) for migration, temporary-file retention, macOS signing requirements and remaining limits. The encrypted history format is not readable by older versions.
