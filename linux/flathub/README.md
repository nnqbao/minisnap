# Publishing MiniSnap on Flathub

Flathub builds apps from a manifest kept in a repository under the `flathub` organisation. The first submission is a pull request to [flathub/flathub](https://github.com/flathub/flathub); after it is merged, Flathub creates `flathub/io.github.nnqbao.MiniSnap` and every later update is a small pull request there.

## What is already in place

| Flathub requirement | Where |
|---|---|
| App ID under a domain the author controls (`io.github.nnqbao` ↔ github.com/nnqbao) | everywhere |
| AppStream metadata with description, screenshots, releases, OARS rating, branding colours, developer | `linux/data/io.github.nnqbao.MiniSnap.metainfo.xml` |
| Valid metadata and desktop file (`appstreamcli validate`, `desktop-file-validate`) | checked by CI on every push |
| OSI licence (MIT) | `LICENSE` |
| Minimal permissions — no network, no home directory; only `Pictures/MiniSnap`, `Videos/MiniSnap`, Wayland/X11, GPU and the file-manager D-Bus name; screen access only through portals | `linux/packaging/io.github.nnqbao.MiniSnap.yml` |
| No self-updater inside Flatpak (Flathub delivers updates) | the app hides its update check when `FLATPAK_ID` is set |
| All sources pinned with SHA-256 or a git commit | manifest |
| Builds with `flatpak-builder` on the GNOME runtime | CI job `flatpak` |

## Submitting (first time)

1. Publish a release by pushing a tag (for example `v1.7.0`). The release job attaches **`io.github.nnqbao.MiniSnap.yml`** — the Flathub manifest pointing at that tag and its exact commit. (You can also generate it locally: `bash linux/packaging/make-flathub-manifest.sh v1.7.0`.)
2. Make sure the GitHub account has two-factor authentication enabled.
3. Fork <https://github.com/flathub/flathub> **including all branches**, and create a branch from **`new-pr`** (not `master`).
4. Add `io.github.nnqbao.MiniSnap.yml` at the root of that branch and commit.
5. Open a pull request **against `new-pr`** titled `Add io.github.nnqbao.MiniSnap`, and fill in the checklist in the PR template.
6. A bot builds the app (comment `bot, build` to rebuild). Reviewers may ask for changes; push fixes to the same branch.
7. After approval Flathub creates `flathub/io.github.nnqbao.MiniSnap` and invites you as a maintainer. Accept the invitation.

## Updating later

For each new MiniSnap release, open a pull request in `flathub/io.github.nnqbao.MiniSnap` that replaces the manifest with the one attached to the new GitHub release (only the `tag` and `commit` of the `minisnap` module change). Add a `<release>` entry to the metainfo file before tagging.

---

## Tiếng Việt — nộp MiniSnap lên Flathub

**Mọi thứ cần chuẩn bị đã có sẵn trong repo (xem bảng ở trên):**
- metainfo đầy đủ, có ảnh chụp màn hình và ghi chú phát hành;
- quyền tối thiểu: không truy cập mạng, không đụng vào thư mục home;
- không tự cập nhật bên trong Flatpak;
- nguồn được ghim bằng SHA-256 hoặc commit;
- được kiểm tra tự động trên GitHub mỗi lần đẩy code.

**Các bước nộp lần đầu (bạn tự làm bằng tài khoản GitHub của mình):**
1. Phát hành một bản mới bằng cách gắn tag (ví dụ `v1.7.0`). Bản phát hành sẽ kèm file **`io.github.nnqbao.MiniSnap.yml`** dành cho Flathub.
2. Bật xác thực 2 lớp cho tài khoản GitHub.
3. Fork repo <https://github.com/flathub/flathub>, nhớ chọn fork **tất cả các nhánh**. Tạo một nhánh mới từ nhánh **`new-pr`**.
4. Thêm file `io.github.nnqbao.MiniSnap.yml` vào thư mục gốc của nhánh đó rồi commit.
5. Mở pull request vào nhánh **`new-pr`**, tiêu đề `Add io.github.nnqbao.MiniSnap`, và điền đủ checklist trong mẫu.
6. Bot của Flathub sẽ build thử. Người duyệt có thể yêu cầu sửa; bạn đẩy bản sửa lên cùng nhánh đó.
7. Khi được duyệt, Flathub tạo repo `flathub/io.github.nnqbao.MiniSnap` và mời bạn làm người duy trì. Bạn chấp nhận lời mời là xong.

**Các lần cập nhật sau:** mỗi khi phát hành bản mới, mở pull request vào `flathub/io.github.nnqbao.MiniSnap`, thay file cấu hình bằng file đính kèm trong bản phát hành mới. Thực tế chỉ có `tag` và `commit` của MiniSnap thay đổi.
