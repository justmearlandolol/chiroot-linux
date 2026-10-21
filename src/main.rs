use std::cell::Cell;
use std::io::Cursor;
use std::process::Command;
use std::rc::Rc;

use gtk::glib;
use gtk::prelude::*;
use gtk::{Window, WindowType};
use webkit2gtk::{
    NavigationPolicyDecision, NavigationPolicyDecisionExt, NavigationType, PolicyDecision,
    PolicyDecisionExt, PolicyDecisionType, ResponsePolicyDecision, ResponsePolicyDecisionExt,
    SettingsExt, URIRequestExt, URIResponseExt, UserContentInjectedFrames, UserContentManager,
    UserContentManagerExt, UserScript, UserScriptInjectionTime, WebView, WebViewExt,
};

const APP_NAME: &str = "Chiroot";
const APP_URL: &str = "https://www.chiroot.my.id/Main.html";
const HOME_HOST: &str = "chiroot.my.id";
const ICON_PNG: &[u8] = include_bytes!("../assets/chiroot.png");

const UNBLOCK_JS: &str = r#"(function () {
  if (window.__chirootAudioUnblocked) return;
  window.__chirootAudioUnblocked = true;
  function unmute(m) {
    try {
      m.muted = false;
      m.defaultMuted = false;
      m.removeAttribute("muted");
    } catch (e) {}
    try {
      if (m.paused && (m.autoplay || m.dataset.autoplay === "1")) {
        var p = m.play();
        if (p && p.catch) p.catch(function () {});
      }
    } catch (e) {}
  }
  function scan() {
    try {
      var ms = document.querySelectorAll("audio,video");
      for (var i = 0; i < ms.length; i++) unmute(ms[i]);
    } catch (e) {}
  }
  function patch() {
    try {
      if (window.__chirootPlayPatched || !window.HTMLMediaElement) return;
      window.__chirootPlayPatched = true;
      var orig = window.HTMLMediaElement.prototype.play;
      window.HTMLMediaElement.prototype.play = function () {
        var el = this;
        var args = arguments;
        try { el.muted = false; } catch (e) {}
        try {
          var r = orig.apply(el, args);
          if (r && r.then) {
            return r.then(undefined, function () {
              try { el.muted = false; } catch (e) {}
              return orig.apply(el, args);
            });
          }
          return r;
        } catch (e) {
          return Promise.resolve();
        }
      };
    } catch (e) {}
  }
  function unlock() {
    patch();
    scan();
    try {
      if (typeof window.__chirootOnUnlock === "function") window.__chirootOnUnlock();
    } catch (e) {}
  }
  try {
    new MutationObserver(function () {
      scan();
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
  var evts = ["pointerdown", "mousedown", "touchstart", "keydown", "click", "play", "canplay"];
  for (var i = 0; i < evts.length; i++) {
    try { document.addEventListener(evts[i], unlock, true); } catch (e) {}
    try { window.addEventListener(evts[i], unlock, true); } catch (e) {}
  }
  try { document.addEventListener("DOMContentLoaded", unlock); } catch (e) {}
  try { window.addEventListener("load", unlock); } catch (e) {}
  unlock();
  setInterval(scan, 1500);
})();"#;

const DOWNLOAD_EXTS: [&str; 15] = [
    ".deb", ".rpm", ".appimage", ".apk", ".exe", ".msi", ".zip", ".tar", ".gz", ".tgz", ".sh",
    ".run", ".7z", ".rar", ".dmg",
];

fn open_external(uri: &str) {
    if gtk::gio::AppInfo::launch_default_for_uri(uri, None::<&gtk::gio::AppLaunchContext>).is_ok() {
        return;
    }
    let _ = Command::new("xdg-open").arg(uri).spawn();
}

fn host_allowed(uri: &str) -> bool {
    let rest = uri
        .strip_prefix("https://")
        .or_else(|| uri.strip_prefix("http://"));
    match rest {
        Some(rest) => {
            let host = rest.split(['/', '?', '#']).next().unwrap_or("");
            let host_lower = host.to_ascii_lowercase();
            host_lower == HOME_HOST || host_lower.ends_with(&format!(".{HOME_HOST}"))
        }
        None => uri.starts_with("about:") || uri.starts_with("data:") || uri.starts_with("blob:"),
    }
}

fn is_download_uri(uri: &str) -> bool {
    let lower = uri.to_ascii_lowercase();
    let path = lower.split(['?', '#']).next().unwrap_or("");
    DOWNLOAD_EXTS.iter().any(|ext| path.ends_with(ext))
}

fn decision_uri(decision: &PolicyDecision) -> String {
    if let Some(nav) = decision.downcast_ref::<NavigationPolicyDecision>() {
        if let Some(action) = nav.navigation_action() {
            if let Some(request) = action.request() {
                if let Some(uri) = request.uri() {
                    return uri.to_string();
                }
            }
        }
    }
    if let Some(resp) = decision.downcast_ref::<ResponsePolicyDecision>() {
        if let Some(response) = resp.response() {
            if let Some(uri) = response.uri() {
                return uri.to_string();
            }
        }
    }
    String::new()
}

fn build_window() -> Window {
    let window = Window::new(WindowType::Toplevel);
    window.set_title(APP_NAME);
    window.set_default_size(1280, 820);
    window.set_position(gtk::WindowPosition::Center);
    window.set_resizable(true);
    if let Ok(pixbuf) = gdk_pixbuf::Pixbuf::from_read(Cursor::new(ICON_PNG)) {
        window.set_icon(Some(&pixbuf));
    }
    window
}

fn build_webview() -> WebView {
    let manager = UserContentManager::new();
    manager.add_script(&UserScript::new(
        UNBLOCK_JS,
        UserContentInjectedFrames::AllFrames,
        UserScriptInjectionTime::Start,
        &[],
        &[],
    ));
    let webview = WebView::with_user_content_manager(&manager);
    if let Some(settings) = WebViewExt::settings(&webview) {
        settings.set_media_playback_requires_user_gesture(false);
        settings.set_enable_media(true);
        settings.set_enable_mediasource(true);
        settings.set_enable_webaudio(true);
        settings.set_enable_media_stream(true);
        settings.set_enable_encrypted_media(true);
        settings.set_enable_html5_local_storage(true);
        settings.set_enable_html5_database(true);
        settings.set_enable_fullscreen(true);
        settings.set_enable_smooth_scrolling(true);
        settings.set_enable_dns_prefetching(true);
        settings.set_enable_developer_extras(false);
        settings.set_auto_load_images(true);
    }
    webview.load_uri(APP_URL);
    webview
}

fn wire_navigation(webview: &WebView) {
    webview.connect_decide_policy(|_, decision, decision_type| {
        match decision_type {
            PolicyDecisionType::NewWindowAction => {
                let uri = decision_uri(decision);
                decision.ignore();
                if !uri.is_empty() && !uri.starts_with("about:") {
                    open_external(&uri);
                }
            }
            PolicyDecisionType::NavigationAction => {
                let uri = decision_uri(decision);
                let interactive = decision
                    .downcast_ref::<NavigationPolicyDecision>()
                    .and_then(|nav| nav.navigation_action())
                    .map(|action| {
                        action.navigation_type() == NavigationType::LinkClicked
                            || action.is_user_gesture()
                    })
                    .unwrap_or(false);
                if is_download_uri(&uri) {
                    decision.ignore();
                    open_external(&uri);
                    return true;
                }
                if interactive && !uri.is_empty() && !host_allowed(&uri) {
                    decision.ignore();
                    open_external(&uri);
                    return true;
                }
                decision.use_();
            }
            PolicyDecisionType::Response => {
                let uri = decision_uri(decision);
                if is_download_uri(&uri) {
                    decision.ignore();
                    open_external(&uri);
                    return true;
                }
                decision.use_();
            }
            _ => decision.use_(),
        }
        true
    });
}

fn wire_window(window: &Window, webview: &WebView) {
    let title_owner = window.downgrade();
    webview.connect_load_changed(move |webview, _| {
        if let Some(window) = title_owner.upgrade() {
            let title = webview
                .title()
                .map(|t| t.to_string())
                .filter(|t| !t.trim().is_empty())
                .unwrap_or_default();
            if title.is_empty() {
                window.set_title(APP_NAME);
            } else {
                window.set_title(&format!("{APP_NAME} \u{2014} {title}"));
            }
        }
    });
    let fullscreen = Rc::new(Cell::new(false));
    let fullscreen_flag = fullscreen.clone();
    window.connect_key_press_event(move |window, event| {
        if event.keyval().name().as_deref() == Some("F11") {
            if fullscreen_flag.get() {
                window.unfullscreen();
                fullscreen_flag.set(false);
            } else {
                window.fullscreen();
                fullscreen_flag.set(true);
            }
            return glib::Propagation::Stop;
        }
        glib::Propagation::Proceed
    });
    window.connect_delete_event(|_, _| {
        gtk::main_quit();
        glib::Propagation::Proceed
    });
}

fn main() {
    if let Err(err) = gtk::init() {
        eprintln!("{APP_NAME}: gtk init failed: {err}");
        std::process::exit(1);
    }
    let window = build_window();
    let webview = build_webview();
    wire_navigation(&webview);
    wire_window(&window, &webview);
    window.add(&webview);
    window.show_all();
    webview.grab_focus();
    gtk::main();
}
