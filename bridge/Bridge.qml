pragma Singleton
import QtQuick

// Engine-wide rendezvous between OmaConnect's service and its bar widget,
// for bar hosts that cannot resolve plugin services themselves.
//
// Under the first-party Omarchy bar, each widget's `bar.shell` facade is
// scoped to the widget's own plugin, so
// `bar.shell.serviceFor("omaconnect")` reaches the live service. Omarchy
// never exposes service resolution to replacement bars: a third-party bar
// is handed a facade whose serviceFor() is a deliberate null stub (only
// the trusted built-in bar can mint service-capable facades). A widget
// hosted by such a bar would therefore never see its service, and there is
// nothing the bar can do about it from its side.
//
// The widget falls back to this singleton instead: the service registers
// itself here on completion, and any widget that cannot reach its host
// picks it up. The host-provided path stays primary, so behaviour under
// the stock shell is unchanged.
QtObject {
    // The live Service.qml instance once it has initialized, or null.
    property var service: null
}
