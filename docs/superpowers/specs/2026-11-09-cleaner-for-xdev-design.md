# Cleaner for xDev: thiết kế

Ngày: 2026-11-09. Trạng thái: **chờ duyệt**.

## Mục tiêu

App macOS native, mã nguồn mở, để phân tích dung lượng đĩa và dọn dẹp an toàn. Ưu tiên máy của lập trình viên
(Xcode, Android, Docker, Node, Rust). Phát hành dạng **DMG** trên GitHub Releases, không qua Mac App Store
(quyết định 2026-11-09), nên app không chạy sandbox và quét được cả ổ đĩa.

Ngoài phạm vi: Mac App Store, Windows/Linux, iOS, gỡ cài đặt app, "tăng tốc máy", dọn RAM, chạy nền hoặc tự khởi động.

## Nền tảng

- Swift 6 (strict concurrency), SwiftUI, macOS 26 trở lên. Máy dev: Xcode 27.2, macOS 27.2.
- Project Xcode sinh từ `project.yml` bằng **XcodeGen**; file `.xcodeproj` không commit.
- Engine tách thành Swift package `CleanerKit` (không có UI), test bằng Swift Testing qua `swift test`.
- Một target app `Cleaner`, không sandbox, Hardened Runtime bật (bắt buộc để notarize).

## Engine (`CleanerKit`)

1. **Scanner**
   - Duyệt thư mục song song (task group, giới hạn số luồng).
   - Tính dung lượng bằng `totalFileAllocatedSize`, tức dung lượng thật trên đĩa, để khớp với `df`.
   - Mỗi cặp (device, inode) chỉ tính một lần, để hard link không bị đếm hai lần.
   - Không đi theo symlink. Không vượt sang volume khác, trừ khi người dùng chọn quét volume đó.
   - Bỏ qua `/System`, `/private/var/vm` và các volume hệ thống chỉ đọc.
   - Báo tiến độ qua `AsyncStream`, huỷ được giữa chừng.
   - Kết quả là cây `Node`: đường dẫn, dung lượng, số file, ngày sửa.
2. **Rules (dọn được):** mỗi quy tắc gồm:
   - mẫu đường dẫn
   - nhóm (dev / hệ thống)
   - mức an toàn (an toàn / cân nhắc)
   - mô tả
   - cách dọn: chuyển vào Thùng rác, hoặc lệnh của chính công cụ đó

   Bộ quy tắc ban đầu:
   - Xcode: DerivedData, Archives (mức cân nhắc), CoreSimulator
     (lệnh `xcrun simctl delete unavailable`), iOS DeviceSupport
   - Android: `~/.gradle/caches`, `~/.android/avd` (cân nhắc), `build/` của project Gradle
   - Node: `~/.npm`, pnpm store (lệnh `pnpm store prune`), `node_modules` (cân nhắc)
   - Rust: `target/` cạnh `Cargo.toml` (lệnh `cargo clean`)
   - Docker build cache (lệnh `docker builder prune -af`)
   - Git worktree không còn thay đổi, kể cả submodule (lệnh `git worktree remove`)
   - Hệ thống: `~/Library/Caches`, `~/Library/Logs`, Thùng rác, file `.dmg`/`.pkg` trong Downloads
3. **File lớn:** các file lớn hơn N MB, lọc theo loại và ngày sửa.
4. **Trùng lặp:** gom theo kích thước, rồi hash 64 KB đầu file, rồi SHA-256 cả file (CryptoKit).
   Clone trên APFS có thể bị báo là trùng; bản đầu ghi rõ giới hạn này trong UI.
5. **Cleaner**
   - Mặc định chỉ chuyển vào Thùng rác (`FileManager.trashItem`). Không xoá vĩnh viễn.
   - Dọn bằng lệnh thì chạy `Process` với đường dẫn tuyệt đối của công cụ, hiện log, huỷ được.
   - Từ chối mọi đường dẫn nằm trong danh sách cấm (`/System`, `/usr`, `/bin`, `/sbin`, `/Library`, thư mục gốc
     của Home, `~/Library` ở cấp gốc).

## Quyền truy cập

- Có Full Disk Access thì quét được cả ổ đĩa.
- Chưa có thì app vẫn quét được những gì macOS cho phép. App ghi rõ các thư mục bị từ chối, kèm nút mở
  System Settings › Privacy & Security › Full Disk Access.

## Màn hình

Sidebar bên trái gồm 5 mục:
1. **Tổng quan:** đã dùng / còn trống của từng volume, top 10 mục lớn nhất, nút Quét.
2. **Thư mục:** treemap, bấm vào để đi sâu, kèm bảng xếp theo dung lượng; có Reveal in Finder.
3. **Dọn được:** danh sách theo nhóm, mỗi mục có tick chọn, tổng dung lượng và nhãn mức an toàn.
   Mục "cân nhắc" không được tick sẵn.
4. **File lớn.**
5. **Trùng lặp.**

Mọi thao tác xoá đều qua một sheet xác nhận: danh sách mục, tổng dung lượng, "sẽ chuyển vào Thùng rác" hoặc lệnh sẽ chạy.
App không thu thập dữ liệu và không kết nối mạng.

## Mã nguồn và phát hành

- **Repo GitHub công khai:** `xdev-asia/cleaner-for-xdev`, license **MIT**.
  - Có README (ảnh chụp màn hình, cách cài, cách build), LICENSE và CI chạy `swift test` trên GitHub Actions.
- **DMG:**
  - Tạo bằng script `scripts/release.sh`: build Release, ký, đóng DMG, notarize, staple.
  - Đưa lên GitHub Releases.
- **Ký và notarize:**
  - Cần chứng chỉ **Developer ID Application**. Máy chưa có chứng chỉ này (mới có Apple Distribution và
    Apple Development); chỉ Account Holder của tài khoản Apple Developer tạo được.
  - Quyết định 2026-11-09: tạo chứng chỉ Developer ID và notarize mọi bản phát hành.
  - Trước khi có chứng chỉ, script vẫn tạo được DMG ký ad-hoc để thử nội bộ, nhưng không đưa lên Releases.
- **Bí mật:**
  - Không có bí mật nào trong repo.
  - Thông tin notarize (`notarytool` keychain profile) chỉ nằm trên máy.

## Kiểm thử

- `CleanerKit`: Swift Testing trên thư mục tạm dựng sẵn. Bao gồm:
  - dung lượng
  - hard link
  - symlink
  - huỷ quét
  - từng quy tắc
  - danh sách cấm
  - tìm trùng lặp
  - trash
  - chạy lệnh (bằng một công cụ giả)
- UI: một XCUITest: quét một thư mục mẫu, mở Dọn được, xác nhận rồi kiểm tra Thùng rác.

## Cập nhật 2026-11-09 (người dùng quyết định)

### Bản Mac App Store
- Quyết định "không qua Mac App Store" ở trên được đổi: thêm target `CleanerAppStore` (bundle
  `asia.xdev.cleaner.appstore`, miễn phí), dùng chung mã nguồn, cờ biên dịch `APP_STORE`.
- Bản Store chạy sandbox, chỉ có quyền `files.user-selected.read-write`:
  - quét thư mục người dùng chọn;
  - chỉ giữ các quy tắc chuyển vào Thùng rác (`Rules.sandboxed`);
  - không chạy lệnh ngoài, không có Full Disk Access.
- Bản DMG giữ đủ tính năng.

### AI chạy trên máy (Apple Intelligence)
- Dùng framework FoundationModels, model chạy trên máy, không gửi dữ liệu lên mạng.
- Prompt chỉ chứa tên, đường dẫn, dung lượng, ngày sửa và quy tắc của app (`AIBrief`); không đọc nội dung file.
- Hai chức năng:
  - **Explain with Apple Intelligence**: giải thích một mục (ở Cleanable, Folders, Large Files, Overview).
  - **Summarise This Scan**: tóm tắt cả lần quét (ở Overview).
- Mức an toàn (Safe/Review) luôn do quy tắc của app quyết định:
  - AI chỉ chép lại mức an toàn, không tự đánh giá.
  - Khi thử, model tự đánh giá thì sai, ví dụ bảo DerivedData là "không an toàn".
- Máy không có Apple Intelligence: app vẫn chạy đủ tính năng, chỉ hiện lý do AI không dùng được.

### Smart Scan (quét nhanh và dọn)
- Mục **Smart Scan** đứng đầu thanh bên và là mục mở mặc định.
- Một nút quét cả thư mục Home. Kết quả gồm các cache cố định và các thư mục build trong dự án (node_modules, build Gradle...).
- Bản DMG quét Home ngay.
- Bản Store hỏi quyền một lần:
  - Lần đầu, hộp chọn thư mục mở sẵn ở Home.
  - App lưu security-scoped bookmark (entitlement `files.bookmarks.app-scope`).
  - Các lần sau bấm một nút là quét. Nút "Change Folder…" để chọn lại.
  - Bookmark hỏng hoặc hết hạn thì app hỏi lại.
- Kết quả chia hai nhóm:
  - **Safe**: chọn sẵn.
  - **Review**: hiện ra nhưng không chọn sẵn.
  - Mục bị chặn hoặc thiếu công cụ không hiện trong Smart Scan; vẫn xem ở Cleanable.
- Nút "Clean <dung lượng>" luôn đi qua hộp xác nhận. Mọi thứ chuyển vào Thùng rác.
- Sau khi dọn, app hiện số dung lượng đã giải phóng và nút "Scan Again".
- AI không tự chạy; nút "Summarise This Scan" vẫn giữ.
- Phần tính toán (nhóm, tổng, lựa chọn mặc định, tổng đã dọn) nằm trong `SmartScanSummary` của CleanerKit và có test.

### Disk Health (sức khoẻ ổ cứng)
- Mục **Disk Health** riêng ở thanh bên, mỗi ổ vật lý một thẻ. Overview có một dòng trạng thái ngắn.
- Nguồn dữ liệu:
  - Ổ NVMe (SSD trong Mac, ổ NVMe gắn ngoài): đọc log SMART 512 byte qua `NVMeSMARTLib` của IOKit. Log gồm mức mòn,
    spare, nhiệt độ, dung lượng đã đọc/ghi, giờ chạy, số lần bật, số lần tắt đột ngột, lỗi media, cảnh báo nghiêm trọng.
  - Ổ khác (SATA, USB): bản DMG lấy trạng thái SMART (Verified / Failing / Not Supported) từ `diskutil info -plist`.
    Bản Store không chạy được diskutil, nên hiện "không đọc được".
  - Mọi ổ: số lỗi đọc/ghi từ lần khởi động gần nhất (thuộc tính `Statistics` trong IORegistry).
- Bản Store xin entitlement `com.apple.security.temporary-exception.iokit-user-client-class` cho
  `AppleNVMeSMARTUserClient` (SSD trong Mac) và `IONVMeSMARTUserClient` (ổ NVMe khác).
  - Đã thử 2026-11-09: không có entitlement thì sandbox chặn (IOKit trả `0xe00002be`); có entitlement thì đọc được.
  - [Inference] Apple có thể hỏi lại hoặc từ chối exception này khi duyệt; ghi lý do trong ghi chú gửi reviewer.
- Mức đánh giá do ngưỡng của app quyết định (`DiskHealth.assess`, có test), không do AI:
  - **Replace**: SMART Failing; cảnh báo nghiêm trọng về spare, độ tin cậy, chế độ chỉ đọc hoặc bộ nhớ dự phòng;
    spare dưới ngưỡng; mức mòn từ 100%.
  - **Watch**: mức mòn từ 80%; có lỗi media; nhiệt độ từ 70 °C hoặc cảnh báo nhiệt; spare cách ngưỡng không quá 10;
    có lỗi đọc/ghi từ lần khởi động.
  - **Good**: không có điều nào ở trên.
  - **Unknown**: không đọc được dữ liệu.
- AI (Apple Intelligence, chạy trên máy) tự viết đánh giá khi mở mục Disk Health; có nút "Assess Again".
  Prompt chỉ có các con số và mức đánh giá của app. AI chép lại mức đánh giá, không tự đánh giá.
