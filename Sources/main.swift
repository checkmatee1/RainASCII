import Foundation
import AVFoundation
import Darwin

var interrupted: sig_atomic_t = 0
let esc = "\u{1B}["
struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}
func write(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
func message(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
let usage = """
雨爱 · macOS ASCII
用法：rainLove.command [选项]
  --mute                 静音
  --no-intro             跳过乱码开场
  --cell-aspect 数值      字符宽高比，默认 0.5
  --duration 秒          限制正片播放时长（用于预览）
  --validate             完整检查帧数据及音频，不播放
  --assets 目录          指定素材目录
  --help                 显示帮助
Q / Esc / Ctrl+C 退出；调整窗口大小可自动适配。
"""
struct Options {
    var mute = false, intro = true, validate = false
    var aspect = 0.5
    var duration: Double?
    var assets = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets")
    init() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--help", "-h": write(usage + "\n"); exit(0)
            case "--mute": mute = true
            case "--no-intro": intro = false
            case "--validate": validate = true
            case "--cell-aspect", "--duration", "--assets":
                i += 1
                guard i < args.count else { throw Failure("\(arg) 缺少参数") }
                if arg == "--assets" {
                    assets = URL(fileURLWithPath: args[i], isDirectory: true)
                } else {
                    guard let value = Double(args[i]), value.isFinite, value > 0 else {
                        throw Failure("\(arg) 需要有限正数")
                    }
                    if arg == "--cell-aspect" {
                        guard value >= 0.1 && value <= 2 else { throw Failure("字符宽高比范围为 0.1…2") }
                        aspect = value
                    } else { duration = value }
                }
            default: throw Failure("未知参数：\(arg)；使用 --help 查看帮助")
            }
            i += 1
        }
    }
}
struct Animation {
    let data: Data
    let width: Int, height: Int, fps: Int, frames: Int
    var duration: Double { Double(frames) / Double(fps) }
    init(root: URL) throws {
        let url = root.appendingPathComponent("frames.bin.gz")
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw Failure("缺少可读素材：\(url.path)") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", url.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        var decoded = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 1_048_576)
            if chunk.isEmpty { break }
            if decoded.count + chunk.count > 512 * 1024 * 1024 {
                process.terminate()
                pipe.fileHandleForReading.closeFile()
                process.waitUntilExit()
                throw Failure("动画解压后超过 512 MiB 限制")
            }
            decoded.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure("动画 gzip 解压或校验失败") }
        guard decoded.count >= 20, String(data: decoded.prefix(8), encoding: .ascii) == "YUAI0002" else {
            throw Failure("无效动画文件头")
        }
        func uint(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(decoded[offset + $1]) << ($1 * 8)) }
        }
        let w = uint(8), h = uint(12), f = uint(16)
        guard (1...1920).contains(w), (1...1080).contains(h), (1...60).contains(f) else {
            throw Failure("无效动画尺寸或帧率")
        }
        let payload = decoded.count - 20, size = w * h
        guard payload > 0, payload % size == 0 else { throw Failure("动画为空或末帧不完整") }
        data = decoded; width = w; height = h; fps = f; frames = payload / size
    }
}
final class TerminalSession {
    private var original = termios()
    private var active = false
    private var oldInt: sig_t?, oldTerm: sig_t?, oldTstp: sig_t?
    init() throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw Failure("请在 Terminal 或 iTerm2 中播放；数据检查请使用 --validate")
        }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw Failure("无法读取终端状态") }
        var mode = original
        mode.c_lflag &= ~tcflag_t(ICANON | ECHO)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &mode) == 0 else { throw Failure("无法设置终端输入模式") }
        oldInt = signal(SIGINT) { _ in interrupted = 1 }
        oldTerm = signal(SIGTERM) { _ in interrupted = 1 }
        oldTstp = signal(SIGTSTP, SIG_IGN)
        active = true
        write("\(esc)?1049h\(esc)?25l\(esc)0m\(esc)40m\(esc)2J\(esc)H")
    }
    func close() {
        guard active else { return }
        write("\(esc)0m\(esc)?25h\(esc)?1049l")
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        signal(SIGINT, oldInt); signal(SIGTERM, oldTerm); signal(SIGTSTP, oldTstp)
        active = false
    }
    deinit { close() }
    func shouldQuit() -> Bool {
        if interrupted != 0 { return true }
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        if poll(&descriptor, 1, 0) > 0 {
            if descriptor.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { return true }
            if descriptor.revents & Int16(POLLIN) != 0 {
                var bytes = [UInt8](repeating: 0, count: 64)
                let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                if count == 0 { return true }
                if count > 0 { return bytes.prefix(count).contains { $0 == 27 || $0 == 113 || $0 == 81 } }
            }
        }
        return false
    }
    func size() -> (Int, Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else { return (80, 23) }
        return (min(800, max(1, Int(size.ws_col))), min(300, max(1, Int(size.ws_row) - 1)))
    }
}
func monotonicTime() -> Double { ProcessInfo.processInfo.systemUptime }
func loading(_ terminal: TerminalSession) -> Bool {
    let start = monotonicTime(), glyphs = Array("0123456789ABCDEF#$%&/\\:+?><{}[]")
    var tick = 0
    while monotonicTime() - start < 3.2 {
        if terminal.shouldQuit() { return false }
        let t = monotonicTime() - start, (cols, rows) = terminal.size()
        let fade = min(1, max(0, (3.2 - t) / 0.5))
        var output = "\(esc)2J"
        for y in 0..<rows {
            let shade = Int((35 + 150 * (0.5 + 0.5 * sin(Double(y) * 0.2 - t * 7))) * fade)
            output += "\(esc)\(y + 1);1H\(esc)38;2;\(shade);\(shade);\(shade)m"
            for x in 0..<cols {
                let head = (tick * (1 + x % 3) + x * 13) % (rows + 16)
                output.append((head - y + rows + 16) % (rows + 16) < 12 ? glyphs.randomElement()! : " ")
            }
        }
        if t < 2.7 && cols >= 44 && rows >= 8 {
            let width = min(56, cols - 4), left = (cols - width) / 2 + 1, top = rows / 2
            let progress = Int(min(1, t / 2.7) * Double(width - 2))
            output += "\(esc)\(top);\(left)H\(esc)97m" + String("[ FRAME SYNC / SYMBOL STREAM / AUDIO CLOCK ]".prefix(width))
            output += "\(esc)\(top + 1);\(left)H[" + String(repeating: "=", count: progress) + String(repeating: " ", count: width - 2 - progress) + "]"
        }
        write(output); tick += 1; Thread.sleep(forTimeInterval: 0.04)
    }
    write("\(esc)2J\(esc)H")
    return true
}
final class Renderer {
    var previous = ""
    let glyphs = [" ", ".,`'", ":;-_", "~^+=", "/\\<>|", "()[]{}", "!?%$&", "0123456789", "ABCDEFabcdef", "@#MW8"].map { Array($0.utf8) }
    let colors = (0..<16).map { i in "\(esc)38;2;\(min(255, i * 17 + 40));\(min(255, i * 17 + 40));\(min(255, i * 17 + 40))m" }
    func draw(_ animation: Animation, index: Int, terminal: TerminalSession, aspect: Double) {
        let (cw, rh) = terminal.size()
        let imageAspect = Double(animation.width) / Double(animation.height)
        let cols = max(1, min(cw, Int(floor(Double(rh) * imageAspect / aspect))))
        let rows = max(1, min(rh, Int((Double(cols) * aspect / imageAspect).rounded())))
        let left = (cw - cols) / 2, top = (rh - rows) / 2
        let key = "\(cw),\(rh)"
        var output = key == previous ? "" : "\(esc)2J"
        previous = key
        let xs = (0..<cols).map { min(animation.width - 1, Int((Double($0) + 0.5) * Double(animation.width) / Double(cols))) }
        let frameOffset = 20 + index * animation.width * animation.height
        animation.data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var last = -1
            for y in 0..<rows {
                output += "\(esc)\(top + y + 1);\(left + 1)H"
                let a = min(animation.height - 1, Int((Double(y * 2) + 0.5) * Double(animation.height) / Double(rows * 2)))
                let b = min(animation.height - 1, Int((Double(y * 2 + 1) + 0.5) * Double(animation.height) / Double(rows * 2)))
                for x in 0..<cols {
                    let gray = (Int(buffer[frameOffset + a * animation.width + xs[x]]) + Int(buffer[frameOffset + b * animation.width + xs[x]])) / 2
                    let bucket = gray * 16 / 256
                    if bucket != last { output += colors[bucket]; last = bucket }
                    let choices = glyphs[min(9, gray * 10 / 256)]
                    let hash = (x * 73) ^ (y * 151) ^ (x * y * 7)
                    output.append(Character(UnicodeScalar(choices[hash % choices.count])))
                }
            }
        }
        write(output)
    }
}
func run() throws {
    let options = try Options()
    if !options.validate && (isatty(STDIN_FILENO) != 1 || isatty(STDOUT_FILENO) != 1) {
        throw Failure("请在终端中播放；检查素材可使用 --validate")
    }
    message("正在加载本地动画…")
    let animation = try Animation(root: options.assets)
    let audioURL = options.assets.appendingPathComponent("audio.wav")
    var audio: AVAudioPlayer?
    if options.validate || !options.mute {
        audio = try AVAudioPlayer(contentsOf: audioURL)
        guard let audio, audio.duration > 0 else { throw Failure("音频为空或无法解码") }
        guard abs(audio.duration - animation.duration) < 1 else { throw Failure("音画时长差异超过 1 秒") }
        if !options.validate && !audio.prepareToPlay() { throw Failure("音频设备准备失败；可尝试 --mute") }
    }
    if options.validate {
        write(String(format: "PASS: %d 帧，%d×%d，%d fps，动画 %.3fs，音频 %.3fs\n", animation.frames, animation.width, animation.height, animation.fps, animation.duration, audio!.duration))
        return
    }
    let terminal = try TerminalSession()
    defer { audio?.stop(); terminal.close() }
    if options.intro && !loading(terminal) { return }
    if terminal.shouldQuit() { return }
    if let audio, !audio.play() { throw Failure("音频播放失败；可尝试 --mute") }
    let start = monotonicTime(), renderer = Renderer()
    let end = min(animation.duration, options.duration ?? animation.duration)
    var last = -1, drawn = 0
    while true {
        if terminal.shouldQuit() { break }
        let wall = monotonicTime() - start
        let elapsed = audio?.isPlaying == true ? audio!.currentTime : wall
        if elapsed >= end { break }
        let index = min(animation.frames - 1, max(0, Int(elapsed * Double(animation.fps))))
        if index != last {
            renderer.draw(animation, index: index, terminal: terminal, aspect: options.aspect)
            last = index; drawn += 1
        }
        Thread.sleep(forTimeInterval: 0.003)
    }
    audio?.stop(); terminal.close()
    message(String(format: "播放结束：%.2fs，绘制 %d 帧", monotonicTime() - start, drawn))
}
do { try run() }
catch { message("错误：\(error)"); exit(1) }
