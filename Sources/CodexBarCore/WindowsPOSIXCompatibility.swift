#if os(Windows)
import Foundation
import ucrt
import WinSDK

// These declarations intentionally mirror the C spellings and signatures used
// by the shared Unix-oriented host layer.
// swiftlint:disable type_name function_parameter_count

// Keep the provider and parsing layers platform-neutral while the host layer
// supplies the small POSIX-shaped surface they use. Process launching that
// needs real Windows semantics is implemented with Foundation.Process; the
// spawn and PTY entry points below deliberately report ENOSYS so callers fail
// soft instead of attempting Unix behavior on Windows.
package typealias pid_t = Int32
typealias mode_t = Int32
typealias id_t = UInt32

let O_CLOEXEC = Int32(_O_NOINHERIT)
let O_NONBLOCK: Int32 = 0
let S_IRUSR: Int32 = 0o400
let S_IWUSR: Int32 = 0o200
let F_GETFD: Int32 = 1
let F_SETFD: Int32 = 2
let F_SETFL: Int32 = 4
let F_DUPFD_CLOEXEC: Int32 = 1030
let FD_CLOEXEC: Int32 = 1
let LOCK_EX: Int32 = 2
let LOCK_UN: Int32 = 8
let SIGKILL: Int32 = 9
let SIGHUP: Int32 = 1
let PATH_MAX: Int32 = 32768
let AT_FDCWD: Int32 = -100
let WNOHANG: Int32 = 1
let WEXITED: Int32 = 4
let WNOWAIT: Int32 = 0x0100_0000
let P_PID: Int32 = 1
let POSIX_SPAWN_SETPGROUP: Int32 = 0x0002
let POSIX_SPAWN_SETSIGDEF: Int32 = 0x0004
let POSIX_SPAWN_SETSIGMASK: Int32 = 0x0008
let _SC_CLK_TCK: Int32 = 2

struct winsize {
    var ws_row: UInt16
    var ws_col: UInt16
    var ws_xpixel: UInt16
    var ws_ypixel: UInt16
}

struct sigset_t {
    var value: UInt64 = 0
}

struct siginfo_t {
    var si_status: Int32 = 0
}

struct posix_spawn_file_actions_t {
    var unused: UInt8 = 0
}

struct posix_spawnattr_t {
    var unused: UInt8 = 0
}

@discardableResult
func usleep(_ microseconds: UInt32) -> Int32 {
    guard microseconds > 0 else { return 0 }
    Sleep(DWORD((UInt64(microseconds) + 999) / 1000))
    return 0
}

@discardableResult
func read(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer!, _ count: Int) -> Int {
    Int(_read(descriptor, buffer, UInt32(clamping: count)))
}

@discardableResult
func write(_ descriptor: Int32, _ buffer: UnsafeRawPointer!, _ count: Int) -> Int {
    Int(_write(descriptor, buffer, UInt32(clamping: count)))
}

@discardableResult
func pipe(_ descriptors: UnsafeMutablePointer<Int32>) -> Int32 {
    _pipe(descriptors, 4096, _O_BINARY | _O_NOINHERIT)
}

@discardableResult
func fchmod(_: Int32, _: mode_t) -> Int32 {
    // Windows protects these files through the user's profile ACL. There is no
    // portable descriptor-level chmod equivalent in the CRT.
    0
}

@discardableResult
func flock(_: Int32, _: Int32) -> Int32 {
    // Every current call site also holds an in-process NSLock. Cross-process
    // Windows locking is handled by the atomic publish path.
    0
}

@discardableResult
func fcntl(_ descriptor: Int32, _ command: Int32) -> Int32 {
    switch command {
    case F_GETFD:
        0
    case F_DUPFD_CLOEXEC:
        _dup(descriptor)
    default:
        0
    }
}

@discardableResult
func fcntl(_: Int32, _: Int32, _: Int32) -> Int32 {
    0
}

@discardableResult
func setenv(_ name: String, _ value: String, _: Int32) -> Int32 {
    _putenv_s(name, value)
}

func getuid() -> UInt32 {
    0
}

func getpgrp() -> pid_t {
    pid_t(bitPattern: GetCurrentProcessId())
}

func getpgid(_ processID: pid_t) -> pid_t {
    processID
}

@discardableResult
func setpgid(_: pid_t, _: pid_t) -> Int32 {
    0
}

@discardableResult
func kill(_ processID: pid_t, _: Int32) -> Int32 {
    guard processID > 0,
          let handle = OpenProcess(DWORD(PROCESS_TERMINATE), false, DWORD(bitPattern: processID))
    else { return -1 }
    defer { CloseHandle(handle) }
    return TerminateProcess(handle, 1) ? 0 : -1
}

func sysconf(_ name: Int32) -> Int {
    name == _SC_CLK_TCK ? 100 : -1
}

@discardableResult
func sigemptyset(_ set: inout sigset_t) -> Int32 {
    set.value = 0
    return 0
}

@discardableResult
func sigaddset(_ set: inout sigset_t, _ signal: Int32) -> Int32 {
    guard signal >= 0, signal < 64 else { return -1 }
    set.value |= UInt64(1) << UInt64(signal)
    return 0
}

@discardableResult
func waitpid(_: pid_t, _: inout Int32, _: Int32) -> pid_t {
    -1
}

@discardableResult
func waitid(_: Int32, _: id_t, _: inout siginfo_t, _: Int32) -> Int32 {
    -1
}

@discardableResult
func fstatat(_: Int32, _: UnsafePointer<CChar>, _: UnsafeMutablePointer<stat>, _: Int32) -> Int32 {
    -1
}

@discardableResult
func openpty(
    _: inout Int32,
    _: inout Int32,
    _: UnsafeMutableRawPointer?,
    _: UnsafeMutableRawPointer?,
    _: inout winsize) -> Int32
{
    ucrt._set_errno(ENOSYS)
    return -1
}

@discardableResult
func posix_spawn_file_actions_init(_: inout posix_spawn_file_actions_t) -> Int32 {
    0
}

@discardableResult
func posix_spawn_file_actions_destroy(_: inout posix_spawn_file_actions_t) -> Int32 {
    0
}

@discardableResult
func posix_spawn_file_actions_addopen(
    _: inout posix_spawn_file_actions_t,
    _: Int32,
    _: String,
    _: Int32,
    _: Int32) -> Int32
{
    0
}

@discardableResult
func posix_spawn_file_actions_adddup2(
    _: inout posix_spawn_file_actions_t,
    _: Int32,
    _: Int32) -> Int32
{
    0
}

@discardableResult
func posix_spawn_file_actions_addclose(_: inout posix_spawn_file_actions_t, _: Int32) -> Int32 {
    0
}

@discardableResult
func posix_spawn_file_actions_addchdir_np(
    _: inout posix_spawn_file_actions_t,
    _: UnsafePointer<CChar>) -> Int32
{
    ENOSYS
}

@discardableResult
func posix_spawnattr_init(_: inout posix_spawnattr_t) -> Int32 {
    0
}

@discardableResult
func posix_spawnattr_destroy(_: inout posix_spawnattr_t) -> Int32 {
    0
}

@discardableResult
func posix_spawnattr_setsigmask(_: inout posix_spawnattr_t, _: inout sigset_t) -> Int32 {
    0
}

@discardableResult
func posix_spawnattr_setsigdefault(_: inout posix_spawnattr_t, _: inout sigset_t) -> Int32 {
    0
}

@discardableResult
func posix_spawnattr_setflags(_: inout posix_spawnattr_t, _: Int16) -> Int32 {
    0
}

@discardableResult
func posix_spawnattr_setpgroup(_: inout posix_spawnattr_t, _: pid_t) -> Int32 {
    0
}

@discardableResult
func posix_spawn(
    _: inout pid_t,
    _: UnsafePointer<CChar>,
    _: inout posix_spawn_file_actions_t,
    _: inout posix_spawnattr_t,
    _: [UnsafeMutablePointer<CChar>?],
    _: [UnsafeMutablePointer<CChar>?]) -> Int32
{
    ENOSYS
}
// swiftlint:enable type_name function_parameter_count
#endif
