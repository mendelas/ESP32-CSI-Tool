# CSI 取得結果

実験日: 2026-06-01 / 構成: active_ap (RX, /dev/ttyUSB0) ← active_sta (TX, /dev/ttyUSB1)
取得: `python_utils/capture_csi.py` で10秒 / 描画: `python_utils/plot_csi.py`

## 実験一覧

| ファイル接頭辞 | sta FREERTOS_HZ | console baud | 取得行数 | 実効レート | 備考 |
|---|---|---|---|---|---|
| `11hz_freertos100_baud115200` | 100（初期値） | 115200 | 113 / 10.1s | **11.2 Hz** | tick起因で送信が10Hzに頭打ち |
| `100hz_freertos1000_baud921600` | 1000 | 921600 | 907 / 10.1s | **90.6 Hz**（間隔中央値 10.1ms ≈ 99 Hz） | 設定修正後 |

各接頭辞に `.csv`（生データ）と `.png`（プロット3枚: 振幅ヒートマップ／サブキャリア別平均振幅／パケット間隔ジッタ）。

## 主な知見

- **レートのボトルネックは送信側の FreeRTOS Tick rate**（シリアル/CPUではない）。
  `vTaskDelay()` の引数はミリ秒でなくティックで、`CONFIG_FREERTOS_HZ=100` だと `vTaskDelay(10)` が 100ms = 約10Hz になる。`=1000` で 10ms = 約100Hz。
- console baud を上げるには `CONFIG_ESP_CONSOLE_UART_CUSTOM=y` が必要（`..._DEFAULT=y` のままだと 115200 に戻る）。
- 11Hz→90Hz でCSIの物理構造（ガードバンド/DCヌル/64サブキャリア）は不変。サンプリング密度のみ向上。
- 100Hz級まではこの構成で実用的。それ以上は要コード改造（callback内でCSV化しない／バイナリ＋別タスク送出／SD・UDP出力／LLTFのみ）。

## CSVフォーマット（要点）
1行 = 1パケット。先頭列群はメタ情報、最終列 `[...]` が CSI 生データ（int8 の `imag real imag real ...` 並び）。
振幅 = √(imag² + real²)、サブキャリア 64本（LLTF/HT20）。列名は各CSVの1行目ヘッダ参照。
