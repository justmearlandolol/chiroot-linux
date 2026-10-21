Name: chiroot
Version: 1.0.0
Release: 1
Summary: Chiroot Free Audio Player Tanpa Iklan
License: MIT
URL: https://www.chiroot.my.id
BuildArch: x86_64

%description
Chiroot Free Audio Player Tanpa Iklan - aplikasi desktop Linux berbasis webview.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_datadir}/applications
mkdir -p %{buildroot}%{_datadir}/pixmaps
mkdir -p %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
mkdir -p %{buildroot}%{_datadir}/icons/hicolor/64x64/apps
install -m 755 %{_sourcedir}/usr/bin/chiroot %{buildroot}%{_bindir}/chiroot
install -m 644 %{_sourcedir}/usr/share/applications/chiroot.desktop %{buildroot}%{_datadir}/applications/chiroot.desktop
install -m 644 %{_sourcedir}/usr/share/pixmaps/chiroot.png %{buildroot}%{_datadir}/pixmaps/chiroot.png
install -m 644 %{_sourcedir}/usr/share/icons/hicolor/scalable/apps/chiroot.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/chiroot.svg
install -m 644 %{_sourcedir}/usr/share/icons/hicolor/64x64/apps/chiroot.png %{buildroot}%{_datadir}/icons/hicolor/64x64/apps/chiroot.png

%files
%{_bindir}/chiroot
%{_datadir}/applications/chiroot.desktop
%{_datadir}/pixmaps/chiroot.png
%{_datadir}/icons/hicolor/scalable/apps/chiroot.svg
%{_datadir}/icons/hicolor/64x64/apps/chiroot.png
