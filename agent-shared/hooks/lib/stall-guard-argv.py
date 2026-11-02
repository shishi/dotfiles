# Windows のプロセスの起動引数を、argv の配列として NUL 区切りで標準出力に出す。
#   python stall-guard-argv.py <pid>
# stall-guard の見張りが、本体 (CLAUDE_PID) が非ストリーミングの -p で動いているかを、
# 本体が asyncRewake を背景で走らせるかを決める条件と同じ形で見分けるために使う。
# 読めなければ何も出さずに 1 で終わる (呼び出し側は見張りを続ける)。
import ctypes
import sys
from ctypes import wintypes

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_COMMAND_LINE_INFORMATION = 60


class UnicodeString(ctypes.Structure):
    _fields_ = [("Length", wintypes.USHORT), ("MaximumLength", wintypes.USHORT), ("Buffer", ctypes.c_void_p)]


def command_line(pid):
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    nt = ctypes.WinDLL("ntdll")
    k32.OpenProcess.restype = wintypes.HANDLE
    handle = k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None
    try:
        size = wintypes.ULONG(0)
        nt.NtQueryInformationProcess(handle, PROCESS_COMMAND_LINE_INFORMATION, None, 0, ctypes.byref(size))
        if not size.value:
            return None
        buf = ctypes.create_string_buffer(size.value)
        if nt.NtQueryInformationProcess(handle, PROCESS_COMMAND_LINE_INFORMATION, buf, size, ctypes.byref(size)) != 0:
            return None
    finally:
        k32.CloseHandle(handle)
    us = UnicodeString.from_buffer(buf)
    return ctypes.wstring_at(us.Buffer, us.Length // 2)


def split_args(line):
    # 文字列の照合で引数を切り出さず、本体と同じ Windows の規則で argv に分ける。
    shell32 = ctypes.WinDLL("shell32")
    k32 = ctypes.WinDLL("kernel32")
    shell32.CommandLineToArgvW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(ctypes.c_int)]
    shell32.CommandLineToArgvW.restype = ctypes.POINTER(wintypes.LPWSTR)
    k32.LocalFree.argtypes = [ctypes.c_void_p]
    count = ctypes.c_int(0)
    arr = shell32.CommandLineToArgvW(line, ctypes.byref(count))
    if not arr:
        return None
    try:
        return [arr[i] for i in range(count.value)]
    finally:
        k32.LocalFree(ctypes.cast(arr, ctypes.c_void_p))


def main():
    try:
        line = command_line(int(sys.argv[1]))
        args = split_args(line) if line else None
    except (ValueError, IndexError, OSError, AttributeError):
        return 1
    if not args:
        return 1
    sys.stdout.buffer.write(b"".join(a.encode("utf-8") + b"\0" for a in args))
    return 0


if __name__ == "__main__":
    sys.exit(main())
