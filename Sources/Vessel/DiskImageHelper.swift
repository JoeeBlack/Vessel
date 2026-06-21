import Foundation

public struct DiskImageHelper {
    public static func readUserData(from url: URL) throws -> Data? {
        let isRaw = url.pathExtension.localizedCaseInsensitiveCompare("raw") == .orderedSame
        if isRaw {
            // Gracefully fail for RAW formats.
            print("Skipping user data read: RAW format is not supported.")
            return nil
        }

        do {
            // Simulate reading user data which might throw DiskImages2 error 45
            // In reality, this would be a call to a framework function.
            return try performReadUserData(from: url)
        } catch let error as NSError where error.domain == "DiskImages2" && error.code == 45 {
            print("Caught DiskImages2 error 45: User data is not supported in this image format. Skipping gracefully.")
            return nil
        } catch {
            throw error
        }
    }

    private static func performReadUserData(from url: URL) throws -> Data? {
        // Placeholder for actual implementation.
        // It could throw an NSError like:
        // throw NSError(domain: "DiskImages2", code: 45, userInfo: [NSLocalizedDescriptionKey: "User data is not supported in this image format"])
        return nil
    }
}
