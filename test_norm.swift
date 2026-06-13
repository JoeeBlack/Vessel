import Foundation

func normalize(reference: String) -> String {
    var ref = reference
    let parts = ref.split(separator: "/")
    if parts.isEmpty { return ref }
    
    let firstPart = String(parts[0])
    if !firstPart.contains(".") && firstPart != "localhost" {
        if parts.count == 1 {
            ref = "docker.io/library/\(ref)"
        } else {
            ref = "docker.io/\(ref)"
        }
    }
    
    if !ref.contains(":") {
        ref += ":latest"
    }
    return ref
}

print("alpine:latest ->", normalize(reference: "alpine:latest"))
print("nginx ->", normalize(reference: "nginx"))
