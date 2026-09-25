"""窗口 resize 稳定性回归: 启动 exe -> 连续 45 次调整大小 -> 检查进程存活。
用法: python test/resize_repro.py
"""
import ctypes
import os
import subprocess
import time
from ctypes import wintypes

u = ctypes.windll.user32
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 脚本在 test/ 下
EXE = os.path.join(ROOT, "build", "windows", "x64", "runner", "Release", "my_bus_app.exe")

detached = 0x00000008 | 0x00000200 | 0x08000000
p = subprocess.Popen([EXE], creationflags=detached, cwd=os.path.dirname(EXE))
pid = p.pid
print("pid", pid)
time.sleep(7)

hwnd = None


def cb(h, _):
    global hwnd
    pp = wintypes.DWORD()
    u.GetWindowThreadProcessId(h, ctypes.byref(pp))
    r = wintypes.RECT()
    u.GetWindowRect(h, ctypes.byref(r))
    if pp.value == pid and u.IsWindowVisible(h) and (r.right - r.left) > 100:
        hwnd = h
    return True


u.EnumWindows(EnumWindowsProc(cb), 0)
print("hwnd:", hwnd)
if not hwnd:
    print("FAIL: no window")
    p.kill()
    raise SystemExit(1)

alive = True
seq = [(w, h) for w in range(420, 1300, 60) for h in (900, 500, 1100)]
for i, (w, h) in enumerate(seq):
    u.SetWindowPos(hwnd, 0, 40, 40, w, h, 0x0040)
    time.sleep(0.08)
    if i % 5 == 4:
        r = subprocess.run(["tasklist", "/FI", f"PID eq {pid}"], capture_output=True)
        if str(pid) not in r.stdout.decode("gbk", "replace"):
            print(f"CRASHED at resize step {i + 1}")
            alive = False
            break
        print(f"step {i + 1}: alive")

r = subprocess.run(["tasklist", "/FI", f"PID eq {pid}"], capture_output=True)
alive = str(pid) in r.stdout.decode("gbk", "replace")
print("result:", "ALIVE (no crash)" if alive else "CRASHED")
subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
raise SystemExit(0 if alive else 2)
