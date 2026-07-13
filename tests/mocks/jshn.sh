#!/bin/sh
# Minimal host-test stand-in. Package builds and router tests use OpenWrt jshn.

json_init() { :; }
json_add_int() { :; }
json_add_string() { :; }
json_add_array() { :; }
json_add_object() { :; }
json_close_array() { :; }
json_close_object() { :; }
json_dump() { printf '%s\n' '{}'; }
