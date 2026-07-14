# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_NAME:=tgbot
PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=kochiya

include $(INCLUDE_DIR)/package.mk

define Package/tgbot
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Instant Messaging
  TITLE:=Telegram bot for OpenWrt status and Wake-on-LAN
  URL:=https://github.com/besire/my-openwrt-tgbot
  DEPENDS:=+ca-bundle +coreutils-od +curl +etherwake +jshn +jsonfilter +ubus +uci
  PKGARCH:=all
endef

define Package/tgbot/description
 A small BusyBox ash Telegram bot for reporting OpenWrt status and waking
 configured LAN devices through etherwake.
endef

define Package/tgbot/conffiles
/etc/config/tgbot
endef

define Build/Compile
endef

define Package/tgbot/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/tgbot $(1)/etc/config/tgbot
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/tgbot $(1)/etc/init.d/tgbot
	$(INSTALL_DIR) $(1)/usr/libexec/tgbot/lib
	$(INSTALL_DATA) ./files/usr/libexec/tgbot/lib/common.sh $(1)/usr/libexec/tgbot/lib/common.sh
	$(INSTALL_DATA) ./files/usr/libexec/tgbot/lib/telegram.sh $(1)/usr/libexec/tgbot/lib/telegram.sh
	$(INSTALL_DATA) ./files/usr/libexec/tgbot/lib/status.sh $(1)/usr/libexec/tgbot/lib/status.sh
	$(INSTALL_DATA) ./files/usr/libexec/tgbot/lib/wol.sh $(1)/usr/libexec/tgbot/lib/wol.sh
	$(INSTALL_BIN) ./files/usr/libexec/tgbot/tgbotd $(1)/usr/libexec/tgbot/tgbotd
	$(INSTALL_BIN) ./files/usr/libexec/tgbot/validate $(1)/usr/libexec/tgbot/validate
	$(INSTALL_BIN) ./files/usr/libexec/tgbot/test-api $(1)/usr/libexec/tgbot/test-api
	$(INSTALL_BIN) ./files/usr/libexec/tgbot/apply $(1)/usr/libexec/tgbot/apply
endef

$(eval $(call BuildPackage,tgbot))
