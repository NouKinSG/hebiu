import HebiuKit
import Foundation

/// 让后台程序设置的光标也能生效（系统默认只认前台程序的）。
/// 用的是 macOS 内部接口，只对 hebiu 自己的连接生效；找不到这个接口就什么都不做
enum BackgroundCursor {
    static func enable() {
        let handle = dlopen(nil, RTLD_NOW)
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let connSym = dlsym(handle, "_CGSDefaultConnection"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else {
            Log.write("background cursor: API not found, skipped")
            return
        }
        let conn = unsafeBitCast(connSym, to: DefaultConnection.self)()
        let err = unsafeBitCast(setSym, to: SetProperty.self)(conn, conn, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        Log.write("background cursor: \(err == 0 ? "on" : "failed (\(err))")")
    }
}
