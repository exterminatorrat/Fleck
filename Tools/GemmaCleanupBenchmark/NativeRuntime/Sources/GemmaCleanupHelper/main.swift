import Foundation

#if os(macOS)
import Darwin
#endif

enum GemmaCleanupHelperMain {
    static func main() async {
        #if os(macOS) && arch(arm64)
        await run()
        #else
        terminate(with: .unsupportedPlatform)
        #endif
    }

    #if os(macOS) && arch(arm64)
    private static func run() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, arguments[0] == "--model-directory" else {
            terminate(with: .invalidModelPath)
        }

        let modelDirectory: GemmaModelDirectory
        do {
            modelDirectory = try GemmaModelDirectory.validate(path: arguments[1])
        } catch let error as GemmaCleanupError {
            terminate(with: error.code)
        } catch {
            terminate(with: .invalidModelPath)
        }

        let engine: MLXGemmaCleanupEngine
        do {
            engine = try await MLXGemmaCleanupEngine.load(directory: modelDirectory)
        } catch let error as GemmaCleanupError {
            terminate(with: error.code)
        } catch {
            terminate(with: .modelLoadFailed)
        }

        let runtime = GemmaCleanupRuntime(engine: engine)
        let writer = Task {
            for await event in runtime.events {
                guard let line = try? GemmaCleanupProtocol.encodeEventLine(event) else {
                    continue
                }
                FileHandle.standardOutput.write(Data(line.utf8))
            }
        }

        var lineBytes: [UInt8] = []
        lineBytes.reserveCapacity(GemmaCleanupLimits.maxLineBytes)
        var lineTooLarge = false
        var didShutdown = false

        do {
            for try await byte in FileHandle.standardInput.bytes {
                if byte == 0x0A {
                    if lineTooLarge {
                        runtime.reportProtocolError(GemmaCleanupError(.lineTooLarge))
                    } else {
                        didShutdown = await process(
                            Data(lineBytes),
                            runtime: runtime
                        )
                    }
                    lineBytes.removeAll(keepingCapacity: true)
                    lineTooLarge = false
                    if didShutdown {
                        break
                    }
                } else if !lineTooLarge {
                    if lineBytes.count >= GemmaCleanupLimits.maxLineBytes {
                        lineTooLarge = true
                    } else {
                        lineBytes.append(byte)
                    }
                }
            }
        } catch {
            runtime.reportProtocolError(GemmaCleanupError(.protocolViolation))
        }

        if !didShutdown {
            if lineTooLarge {
                runtime.reportProtocolError(GemmaCleanupError(.lineTooLarge))
            } else if !lineBytes.isEmpty {
                didShutdown = await process(Data(lineBytes), runtime: runtime)
            }
        }

        if !didShutdown {
            await runtime.shutdown(requestID: "eof")
        }
        await writer.value
    }

    private static func process(
        _ data: Data,
        runtime: GemmaCleanupRuntime
    ) async -> Bool {
        do {
            switch try GemmaCleanupProtocol.decodeRequestData(data) {
            case .cleanup(let request):
                do {
                    _ = try runtime.start(request, operation: .cleanup)
                } catch let error as GemmaCleanupError {
                    runtime.reportProtocolError(error, requestID: request.requestID)
                } catch {
                    runtime.reportProtocolError(
                        GemmaCleanupError(.protocolViolation),
                        requestID: request.requestID
                    )
                }
                return false
            case .route(let request):
                do {
                    _ = try runtime.start(request, operation: .route)
                } catch let error as GemmaCleanupError {
                    runtime.reportProtocolError(error, requestID: request.requestID)
                } catch {
                    runtime.reportProtocolError(
                        GemmaCleanupError(.protocolViolation),
                        requestID: request.requestID
                    )
                }
                return false
            case .cancel(let requestID, let targetRequestID):
                _ = await runtime.cancel(requestID: requestID, targetRequestID: targetRequestID)
                return false
            case .shutdown(let requestID):
                await runtime.shutdown(requestID: requestID)
                return true
            }
        } catch let error as GemmaCleanupError {
            runtime.reportProtocolError(error)
            return false
        } catch {
            runtime.reportProtocolError(GemmaCleanupError(.invalidJSON))
            return false
        }
    }
    #endif

    private static func terminate(with code: GemmaCleanupError.Code) -> Never {
        FileHandle.standardError.write(
            Data("gemma-cleanup-helper: \(code.rawValue)\n".utf8)
        )
        #if os(macOS)
        Darwin.exit(2)
        #else
        fatalError(code.rawValue)
        #endif
    }
}

await GemmaCleanupHelperMain.main()
