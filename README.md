# Monitor iOS

App SwiftUI native cho [alert.huyab.click](https://alert.huyab.click) (Odoo cron
monitor). Không dependency, `.xcodeproj` viết tay, iOS 16+, iPhone.

## Màn hình

| Tab | Làm gì |
|---|---|
| **Cron** | Chọn instance, xem cron sắp chạy / đang trễ. Tự tải lại mỗi 30 giây, sắp theo `nextcall`, tìm theo tên, lọc "chỉ cron trễ". |
| **Instance** | Thêm / sửa / nhân bản / đổi thứ tự instance, gửi mail thử. Swipe để thao tác. |
| **Cài đặt** | Ngưỡng cảnh báo (`alert_delay_minutes`), email đang đăng nhập, đăng xuất. |

Đăng nhập dùng chung SSO `auth.huyab.click`: WKWebView chạy luồng Google, đọc
cookie HttpOnly `huyab_sso` rồi cất vào Keychain.

## Chạy

```bash
xcodebuild test -project Monitor.xcodeproj -scheme Monitor \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 11'
```

Cài lên máy thật (Apple ID free, app hết hạn sau 7 ngày):

```bash
xcodebuild -project Monitor.xcodeproj -scheme Monitor -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd \
  -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team>
xcrun devicectl device install app --device <id> build/dd/Build/Products/Debug-iphoneos/Monitor.app
```

## Cố tình không làm

- Tab **Thống kê** (biểu đồ recharts của bản web).
- Xoá instance: server chưa có endpoint DELETE.
- Bật/tắt `alert_enabled` từng instance: server chưa có endpoint.
