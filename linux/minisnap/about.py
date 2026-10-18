"""About window (Adw.AboutWindow; libadwaita 1.5 has no Adw.AboutDialog yet)."""

from . import _gi  # noqa: F401
from gi.repository import Adw, Gtk

from . import APP_ID, AUTHOR, EMAIL, REPO, VERSION
from .i18n import L


def make_about(app=None, parent=None):
    win = Adw.AboutWindow(
        application_name="MiniSnap",
        application_icon=APP_ID,
        version=VERSION,
        developer_name=AUTHOR,
        developers=[AUTHOR + " <" + EMAIL + ">"],
        website=REPO,
        issue_url=REPO + "/issues",
        support_url="mailto:" + EMAIL,
        license_type=Gtk.License.MIT_X11,
        copyright="© 2026 " + AUTHOR,
        comments=L.t("Đây là phần mềm chụp ảnh, quay phim màn hình miễn phí, mã nguồn mở dành cho mọi người."),
    )
    win.add_link(L.t("Quyền riêng tư: ") + L.t("MiniSnap không thu thập dữ liệu"), REPO + "/blob/main/PRIVACY.md")
    win.add_link(L.t("Mã nguồn: ") + "github.com/nnqbao/minisnap", REPO)
    if parent is not None:
        win.set_transient_for(parent)
    if app is not None:
        win.set_application(app)
    return win
