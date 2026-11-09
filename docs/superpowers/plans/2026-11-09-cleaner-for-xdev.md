# Plan: Cleaner for xDev v0.1 (bản dùng nội bộ)

Spec: `docs/superpowers/specs/2026-11-09-cleaner-for-xdev-design.md`. Mỗi task: viết test đỏ, code cho xanh, refactor.

## Quyết định triển khai

- Cây kết quả chỉ giữ thư mục và file từ 1 MB trở lên. File nhỏ hơn gộp vào dung lượng và số file của thư mục
  cha, để quét cả ổ không tốn hàng GB RAM.
- Quét bằng `lstat` (Darwin): dung lượng = `st_blocks * 512`; hard link nhận diện qua `(st_dev, st_ino)` khi
  `st_nlink > 1`, và chỉ tính một lần.
- Quét `/`: cho phép hai device (`/` và `/System/Volumes/Data`), bỏ qua `/System`, `/dev`, `/Volumes`,
  `/private/var/vm`, để không đếm trùng qua firmlink.
- Mỗi thư mục ghi lại "marker" (`Cargo.toml`, `package.json`, `build.gradle(.kts)`, `.git` là file) để các quy tắc
  nhận ra `target/`, `node_modules/`, `build/` và git worktree.
- Lệnh ngoài (`docker`, `git`, `cargo`, `pnpm`, `xcrun`) tìm theo danh sách thư mục cố định, vì app mở từ Finder
  không có PATH của shell.
- Ký bằng "Apple Development" nếu có, để quyền Full Disk Access không mất sau mỗi lần build lại. Team ID lấy từ
  Keychain lúc build, không ghi vào repo.

## Tasks

1. Khung repo: `Package.swift` (CleanerKit + tests), `project.yml`, `.gitignore`, LICENSE MIT, README.
2. `SafetyGuard`: chặn đường dẫn cấm (test trước).
3. `Scanner`: dung lượng, file nhỏ gộp, hard link, symlink, quyền bị từ chối, marker, huỷ quét.
4. `Treemap`: squarified layout, diện tích tỉ lệ dung lượng, nằm trong khung.
5. `Rules` + `RuleMatcher`: bộ quy tắc trong spec, khớp trên cây đã quét.
6. `ToolLocator` + `CommandRunner` (giao thức, có bản giả cho test); `DockerProbe`, `GitWorktreeProbe`.
7. `LargeFiles`, `DuplicateFinder` (kích thước, hash 64 KB đầu, SHA-256 cả file; bỏ hard link).
8. `Cleaner`: trash qua `SafetyGuard`, chạy lệnh, trả kết quả từng mục.
9. App SwiftUI: Tổng quan, Thư mục (treemap), Dọn được, File lớn, Trùng lặp, sheet xác nhận, banner Full Disk Access.
10. `scripts/build-app.sh`: XcodeGen, xcodebuild Release, ký, đóng DMG. `scripts/release.sh` (Developer ID +
    notarize) để dành khi có chứng chỉ.
11. Kiểm chứng: `swift test` xanh, build app, mở app, quét thử thư mục thật.
