# Copyright (C) 2026
# This is free software, licensed under the MIT License.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-usb-pcie-scan
LUCI_TITLE:=USB/PCIe Device Scanner
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
LUCI_DEPENDS:=+luci-compat +usbutils +pciutils

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
