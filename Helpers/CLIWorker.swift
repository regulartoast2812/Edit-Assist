import Foundation
import Darwin

// Each request owns its process group so Stop also terminates launcher children.
@main
struct CLIWorker {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let executable = args.first, executable.hasPrefix("/"), setpgid(0, 0) == 0 else { exit(126) }
        let pointers = args.map { strdup($0) } + [nil]
        _ = pointers.withUnsafeBufferPointer { execv(executable, $0.baseAddress!) }
        exit(127)
    }
}
