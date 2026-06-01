# ESP32-CSI-Tool 利用ガイド

環境: Ubuntu 24.04 / Python 3.12 / ESP-IDF v4.3 / 作成 2026-06-01

## 0. 全体像

CSIは「**パケットを受信した側**」で計算される。2台構成：

| ディレクトリ | 役割 | 接続先 | ポート | MAC |
|---|---|---|---|---|
| `active_ap` | AP＝**RX（CSI収集）** | PCに繋ぐ | `/dev/ttyUSB0` | `48:e7:29:89:60:38` |
| `active_sta` | STA＝**TX（垂れ流し）** | 繋ぐだけ | `/dev/ttyUSB1` | `48:e7:29:89:3a:50` |

データの流れ：`sta が送信 → ap が受信 → ap の serial に CSI_DATA 出力`

---

## 1. 2種類の環境（混同しないこと）

| 用途 | 実体 | 読み込み/実行方法 |
|---|---|---|
| **ESP-IDF**（build / flash / monitor） | `~/esp/esp-idf` | `. ~/esp/esp-idf/export.sh` |
| **Python解析**（capture / plot） | リポジトリ内 `./venv`（git無視） | `./venv/bin/python ...` |

ESP-IDF v4.3 は Python 3.12 対応で3点修正済み（新PC再構築時のみ必要）：
- `sudo apt install python3-virtualenv`
- `~/esp/esp-idf/requirements.txt` の gdbgui / pygdbmi / python-socketio をコメントアウト（backup: `requirements.txt.bak`）
- ESP-IDF の venv に `setuptools<81` をピン
- ユーザーを `dialout` グループに追加

解析用 `./venv` の再作成：
```bash
cd ~/ESP32-CSI-Tool
python3 -m venv venv
./venv/bin/pip install numpy matplotlib pyserial
```

---

## 2. ターミナルを開くたびに（build/flash 用）

```bash
newgrp dialout                  # dialout未反映時のみ（VSCode本体を再起動すれば不要に）
. ~/esp/esp-idf/export.sh       # 無いと idf.py: command not found
```
エイリアス推奨：
```bash
echo "alias get_idf='. ~/esp/esp-idf/export.sh'" >> ~/.bashrc && source ~/.bashrc
```

---

## 3. ビルド

```bash
cd ~/ESP32-CSI-Tool/active_ap      # または active_sta
idf.py set-target esp32            # 初回のみ
idf.py menuconfig                  # 設定変更時のみ（§6）
idf.py build
```
- クリーンビルド: `idf.py fullclean` / 設定反映のみ: `idf.py reconfigure`

---

## 4. ESP32への書き込み（flash）

**鉄則：1ターミナル＝1ポート。同じポートに monitor を二重に開かない**（`multiple access on port` でクラッシュ）。

```bash
cd ~/ESP32-CSI-Tool/active_ap  && idf.py -p /dev/ttyUSB0 flash   # MAC …60:38
cd ~/ESP32-CSI-Tool/active_sta && idf.py -p /dev/ttyUSB1 flash   # MAC …3a:50
```
- 2台あるので **必ず `-p` でポート明示**。書き込み開始時の `MAC:` で取り違え確認。
- 書き込み＋監視: `idf.py -p /dev/ttyUSB0 flash monitor`（終了 `Ctrl+]`、効かなければ別端末で `ps aux | grep idf_monitor` → `kill <PID>`）。
- `Permission denied: /dev/ttyUSB*` → dialout未反映。`newgrp dialout` してから。

---

## 5. CSIの取得（capture）

リポジトリ追加スクリプト。シリアル直読みで指定秒数だけCSV保存（idf.py monitor不要・自動停止）：
```bash
cd ~/ESP32-CSI-Tool
./venv/bin/python python_utils/capture_csi.py /dev/ttyUSB0 921600 10 results/my_capture.csv
#                                              ポート       baud   秒  出力先
```
- `baud` は **ESP32側のconsole baudと一致**（現状 921600）。
- ポートを使うので **dialout 必須**（`newgrp dialout` 済みの端末で）。

参考：READMEの素朴な方法（idf.py monitor 経由）
```bash
idf.py -p /dev/ttyUSB0 monitor | grep "CSI_DATA" > results/my_capture.csv
idf.py -p /dev/ttyUSB0 monitor | python python_utils/serial_append_time.py > results/my_capture.csv
```

---

## 6. 描画・解析

リポジトリ追加スクリプト（GUI不要・PNG出力）：
```bash
cd ~/ESP32-CSI-Tool
./venv/bin/python python_utils/plot_csi.py results/my_capture.csv results/my_plot.png
```
→ 振幅ヒートマップ／サブキャリア別平均振幅／パケット間隔(ジッタ) の3枚。

既存：`python_utils/parse_csi.py`（CSV→振幅/位相サンプル）、`python_utils/serial_plot_csi_live.py`（リアルタイム可視化）。

---

## 7. 重要なmenuconfig設定

`idf.py menuconfig`（操作：矢印・Enter・`/`検索・`S`保存・`Q`終了）

| 目的 | 項目 | 値 |
|---|---|---|
| **CSIを有効化（必須）** | `Component config > Wi-Fi > WiFi CSI` | 有効化 |
| 送信レートを上げる | `Component config > FreeRTOS > Tick rate (Hz)` | **1000** |
| baudを上げる① | `Component config > ... > Channel for console output` | **Custom UART** |
| baudを上げる② | `UART console baud rate` | **921600** |
| monitor速度 | `Serial flasher config > 'idf.py monitor' baud rate` | 921600 |
| 実験パラメータ | `ESP32 CSI Tool Config`（SSID/PW/CHANNEL/PACKET_RATE） | 任意 |

**ハマりどころ**
- console baud は `CONFIG_ESP_CONSOLE_UART_CUSTOM=y` でないと反映されず115200に戻る（`..._DEFAULT=y` のままだとダメ）。
- `active_ap` と `active_sta` で **SSID/パスワード/チャンネルを一致**（初期値 `myssid`/`mypassword`/ch6 なら自動一致）。
- **送信レートを決めるのは送信側(sta)の `FREERTOS_HZ`**（`vTaskDelay`がティック単位。100→約10Hz、1000→約100Hz）。

---

## 8. サンプリングレートの目安

| 構成 | 実効レート |
|---|---|
| sta FREERTOS_HZ=100 / 115200 | 約11 Hz |
| **sta FREERTOS_HZ=1000 / 921600** | **約90 Hz（実用上の100Hz）** |
| それ以上 | 要コード改造（バイナリ出力・別タスク送出・SD/UDP・LLTFのみ） |

ボトルネックの順：**送信側Tick rate → シリアルbaud → CPU/実装の重さ**。

CSI配列：最終列 `[...]` が int8 の `imag real imag real ...`。振幅 = √(imag²+real²)、サブキャリア 64本（LLTF/HT20）。
