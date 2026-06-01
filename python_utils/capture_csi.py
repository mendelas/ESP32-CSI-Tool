#!/usr/bin/env python3
"""
Capture CSI_DATA lines straight from the ESP32 serial port for a fixed duration
and write them to a CSV file. Reads the port directly via pyserial (no idf.py
monitor needed), so make sure no other process is holding the port.

Usage:
    python capture_csi.py [PORT] [BAUD] [SECONDS] [OUTFILE]
Defaults:
    PORT=/dev/ttyUSB0  BAUD=115200  SECONDS=10  OUTFILE=csi_capture.csv
"""
import sys
import time
import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
BAUD = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
SECONDS = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
OUTFILE = sys.argv[4] if len(sys.argv) > 4 else "csi_capture.csv"

# Same column order the firmware prints (see _components/csi_component.h).
HEADER = ("type,role,mac,rssi,rate,sig_mode,mcs,bandwidth,smoothing,not_sounding,"
          "aggregation,stbc,fec_coding,sgi,noise_floor,ampdu_cnt,channel,"
          "secondary_channel,local_timestamp,ant,sig_len,rx_state,real_time_set,"
          "real_timestamp,len,CSI_DATA")

print(f"Opening {PORT} @ {BAUD} baud, capturing {SECONDS:.0f}s -> {OUTFILE}")
ser = serial.Serial(PORT, BAUD, timeout=1)
n = 0
t0 = time.time()
last_report = t0
with open(OUTFILE, "w") as f:
    f.write(HEADER + "\n")
    while time.time() - t0 < SECONDS:
        line = ser.readline().decode("utf-8", "ignore").strip()
        if line.startswith("CSI_DATA"):
            f.write(line + "\n")
            n += 1
        now = time.time()
        if now - last_report >= 1.0:
            print(f"  {now - t0:4.1f}s  rows={n}")
            last_report = now
ser.close()
elapsed = time.time() - t0
print(f"Done. {n} CSI rows in {elapsed:.1f}s  =  {n / elapsed:.1f} Hz  ->  {OUTFILE}")
