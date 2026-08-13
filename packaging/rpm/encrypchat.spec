# Encrypchat for Fedora. This is a binary repack, not a build from source: compiling the
# client needs the Flutter SDK, which Fedora does not package, so rpmbuild would have no way
# to produce the bundle. scripts/package-rpm.sh builds it first and hands it over as Source0.
#
# Everything the app needs at runtime that is not a system library travels inside the bundle
# and is found through RUNPATH $ORIGIN/lib.

%global appdir  %{_libdir}/%{name}
%global bundle  %{name}-%{version}-linux-x64

# The bundle carries private copies of the Flutter engine, WebRTC and SQLCipher. Announcing
# those as system-wide Provides would let an unrelated package believe its dependency is
# satisfied by a library it cannot load. And the matching Requires have to go too: they name
# sonames that nothing on the system provides, which would make this package uninstallable.
# The exact list is computed from the bundle by the build script — hardcoding it here would
# rot the first time a plugin is added.
%global __provides_exclude_from ^%{appdir}/.*$
%global __requires_exclude %{bundled_sonames}

# The staged binaries were stripped already, so there is nothing left to split out.
%global debug_package %{nil}

Name:           encrypchat
Version:        %{app_version}
Release:        1%{?dist}
Summary:        Decentralized peer-to-peer chat with end-to-end encryption

# Not an open source license: see LICENSE at the repository root. LicenseRef- is how SPDX
# spells "a license that is not on the list", which is the honest tag until that is decided.
License:        LicenseRef-Encrypchat-Proprietary
URL:            https://encrypchat.com
Source0:        %{bundle}.tar.gz
ExclusiveArch:  x86_64

# Found by opening a browser, not by the ELF scanner: url_launcher shells out to xdg-open.
Requires:       xdg-utils
# Secrets go to the Secret Service over D-Bus, which is a running service and not a linked
# library. Without a keyring the app cannot store the database key and refuses to start.
Requires:       libsecret

%description
Encrypchat is a peer-to-peer messenger. Messages, media and keys stay on the device:
there is no account, and no server holds a copy of a conversation. Encryption happens
before anything leaves the device, so an optional relay — used only when the other side
is offline — sees ciphertext and never plaintext.

This package installs the desktop client. What it protects against, and what it does
not, is written down at https://encrypchat.com and in the threat model that ships with
the project.

%prep
%autosetup -n %{bundle}

%install
install -d %{buildroot}%{appdir}
cp -a . %{buildroot}%{appdir}/
chmod 0755 %{buildroot}%{appdir}/encrypchat

# The launcher resolves its own path through /proc/self/exe, which follows symlinks, so the
# engine still finds data/ and lib/ next to the real binary.
install -d %{buildroot}%{_bindir}
ln -s %{appdir}/encrypchat %{buildroot}%{_bindir}/%{name}

# Square 1024 mark on white — generated from logo-mark.png by
# scripts/generate-app-icons.py. A non-square file in a hicolor size
# directory would be a lie about its dimensions.
install -Dpm 0644 data/flutter_assets/assets/brand/app-icon.png \
  %{buildroot}%{_datadir}/icons/hicolor/1024x1024/apps/%{name}.png
install -Dpm 0644 data/flutter_assets/assets/brand/app-icon.png \
  %{buildroot}%{_datadir}/pixmaps/%{name}.png

install -d %{buildroot}%{_datadir}/applications
cat > %{buildroot}%{_datadir}/applications/%{name}.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Encrypchat
Comment=DECENTRALIZED P2P CHAT | ZERO-CLOUD
Exec=encrypchat
Icon=encrypchat
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=encrypchat
EOF

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

%files
%{appdir}
%{_bindir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/1024x1024/apps/%{name}.png
%{_datadir}/pixmaps/%{name}.png

%changelog
* Wed Aug 12 2026 Encrypchat <info@elnerd.com> - 1.0.0-1
- First Fedora package, for testing on real hardware. Unsigned: install with
  `sudo dnf install ./encrypchat-<version>.rpm` and expect no repository behind it.
