# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=kochiya
PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_PO_VERSION:=0.2.0-r1

LUCI_TITLE:=LuCI support for the OpenWrt Telegram bot
LUCI_DEPENDS:=+luci-base +tgbot
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=kochiya
LUCI_URL:=https://github.com/besire/my-openwrt-tgbot

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
