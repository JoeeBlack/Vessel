## 2024-06-13 - [Memory Allocation Optimization]
**Learning:** Using `components(separatedBy:)` in hot paths (like a stats polling loop running every 1 second) causes excessive String and Array allocations because it produces arrays of fully initialized Strings, even for empty tokens.
**Action:** Use `.split(whereSeparator:)` instead of `.components(separatedBy:)` in high-frequency string parsing routines. It returns `Substring` (a zero-allocation view into the original string) and automatically ignores empty items without requiring `.filter { !$0.isEmpty }`.
